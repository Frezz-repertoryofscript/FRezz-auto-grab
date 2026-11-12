import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from remapper.engine import EngineCore, process_stick, compact_steps  # noqa: E402
from remapper.macro import MacroInstance  # noqa: E402
from remapper.profile import default_profile, default_macro, normalize_profile  # noqa: E402

AX0 = {"LX": 0, "LY": 0, "RX": 0, "RY": 0, "L2": 0, "R2": 0}


def run(core, pressed, t, axes=None):
    out, actions = core.process({b: True for b in pressed}, dict(AX0, **(axes or {})), t)
    return out, actions


def macro(**kw):
    m = default_macro(kw.pop("name", "M"))
    m.update(kw)
    return m


def test_identity_and_remap():
    p = default_profile()
    p["buttons"]["CROSS"] = "pad:CIRCLE"
    p["buttons"]["SQUARE"] = "key:space"
    core = EngineCore(p)
    out, _ = run(core, ["CROSS", "SQUARE", "L1"], 0.0)
    assert out.targets == {"pad:CIRCLE", "key:space", "pad:L1"}


def test_analog_trigger_passthrough_and_threshold():
    core = EngineCore(default_profile())
    out, _ = run(core, [], 0.0, {"R2": 0.5})
    assert 0.45 < out.axes["R2"] < 0.55
    assert "pad:R2" not in out.targets
    p = default_profile()
    p["buttons"]["R2"] = "mouse:left"
    core = EngineCore(p)
    assert "mouse:left" in run(core, [], 0.0, {"R2": 0.6})[0].targets
    assert "mouse:left" not in run(core, [], 0.01, {"R2": 0.1})[0].targets


def test_stick_deadzone_and_invert():
    cfg = default_profile()["sticks"]["LEFT"]
    assert process_stick(0.05, 0.0, cfg) == (0.0, 0.0)
    x, _ = process_stick(1.0, 0.0, cfg)
    assert x == 1.0
    cfg["invert_x"] = True
    assert process_stick(1.0, 0.0, cfg)[0] == -1.0


def test_stick_to_keys_and_mouse():
    p = default_profile()
    p["sticks"]["LEFT"]["target"] = "zqsd"
    p["sticks"]["RIGHT"]["target"] = "mouse"
    core = EngineCore(p)
    run(core, [], 0.0)
    out, _ = run(core, [], 0.01, {"LY": -1.0, "RX": 1.0})
    assert "key:z" in out.targets
    assert out.mouse[0] > 0 and out.axes["LY"] == 0


def test_press_macro_timing():
    p = default_profile()
    p["macros"] = [macro(trigger=["TRIANGLE"], steps=[
        {"type": "tap", "targets": ["pad:CROSS"], "ms": 50},
        {"type": "wait", "ms": 30},
        {"type": "tap", "targets": ["key:e"], "ms": 20},
    ])]
    core = EngineCore(p)
    out, _ = run(core, ["TRIANGLE"], 0.0)
    assert "pad:CROSS" in out.targets and "pad:TRIANGLE" not in out.targets  # bloqué
    assert "pad:CROSS" in run(core, [], 0.049)[0].targets
    assert "pad:CROSS" not in run(core, [], 0.051)[0].targets
    assert "key:e" not in run(core, [], 0.079)[0].targets
    assert "key:e" in run(core, [], 0.081)[0].targets
    assert not run(core, [], 0.102)[0].targets
    assert not core.running


def test_repeat_and_speed():
    m = macro(trigger=["CROSS"], repeat=3, speed=2.0,
              steps=[{"type": "tap", "targets": ["pad:R1"], "ms": 100}, {"type": "wait", "ms": 100}])
    p = default_profile()
    p["macros"] = [m]
    core = EngineCore(p)
    presses, last, t = 0, False, 0.0
    run(core, ["CROSS"], t)
    while t < 0.5:
        t += 0.001
        on = "pad:R1" in run(core, [], t)[0].targets
        presses += on and not last
        last = on
    assert presses == 3
    assert not core.running


def test_hold_and_toggle_modes():
    steps = [{"type": "tap", "targets": ["pad:CROSS"], "ms": 10}, {"type": "wait", "ms": 10}]
    p = default_profile()
    p["macros"] = [macro(name="H", trigger=["L1"], mode="hold", repeat=0, steps=steps),
                   macro(name="T", trigger=["R1"], mode="toggle", repeat=0, steps=steps)]
    core = EngineCore(p)
    run(core, ["L1"], 0.0)
    run(core, ["L1"], 0.5)
    assert "H" in core.running
    run(core, [], 0.51)
    assert "H" not in core.running
    run(core, ["R1"], 1.0)
    run(core, [], 1.1)
    assert "T" in core.running
    run(core, ["R1"], 1.2)
    assert "T" not in core.running


def test_combo_priority_and_blocking():
    p = default_profile()
    p["macros"] = [
        macro(name="solo", trigger=["L1"], steps=[{"type": "tap", "targets": ["key:a"], "ms": 100}]),
        macro(name="combo", trigger=["L1", "R1"], steps=[{"type": "tap", "targets": ["key:b"], "ms": 100}]),
    ]
    core = EngineCore(p)
    out, _ = run(core, ["L1", "R1"], 0.0)
    assert "key:b" in out.targets and "key:a" not in out.targets
    assert "pad:L1" not in out.targets and "pad:R1" not in out.targets


def test_double_and_long():
    p = default_profile()
    p["macros"] = [
        macro(name="D", trigger=["CROSS"], mode="double", steps=[{"type": "tap", "targets": ["key:x"], "ms": 50}]),
        macro(name="L", trigger=["CIRCLE"], mode="long", hold_ms=300,
              steps=[{"type": "tap", "targets": ["key:y"], "ms": 50}]),
    ]
    core = EngineCore(p)
    run(core, ["CROSS"], 0.0)
    run(core, [], 0.1)
    assert "key:x" in run(core, ["CROSS"], 0.2)[0].targets
    run(core, [], 0.5)
    run(core, ["CIRCLE"], 1.0)
    assert "key:y" not in run(core, ["CIRCLE"], 1.2)[0].targets
    assert "key:y" in run(core, ["CIRCLE"], 1.31)[0].targets


def test_turbo_hold_and_toggle():
    p = default_profile()
    p["turbo"] = {"CROSS": {"enabled": True, "rate": 10, "mode": "hold"},
                  "SQUARE": {"enabled": True, "rate": 10, "mode": "toggle"}}
    core = EngineCore(p)
    assert "pad:CROSS" in run(core, ["CROSS"], 0.0)[0].targets
    assert "pad:CROSS" not in run(core, ["CROSS"], 0.06)[0].targets
    assert "pad:CROSS" in run(core, ["CROSS"], 0.11)[0].targets
    run(core, ["SQUARE"], 1.0)
    run(core, [], 1.02)
    assert "pad:SQUARE" in run(core, [], 1.11)[0].targets  # continue sans tenir
    run(core, ["SQUARE"], 1.2)
    assert "pad:SQUARE" not in run(core, [], 1.31)[0].targets


def test_button_mapped_to_macro_and_action():
    p = default_profile()
    p["macros"] = [macro(name="Hado", steps=[{"type": "tap", "targets": ["pad:SQUARE"], "ms": 30}])]
    p["buttons"]["R3"] = "macro:Hado"
    p["buttons"]["L3"] = "action:next_profile"
    core = EngineCore(p)
    out, actions = run(core, ["R3", "L3"], 0.0)
    assert "pad:SQUARE" in out.targets and actions == ["next_profile"]


def test_hotkeys_pause():
    core = EngineCore(default_profile())
    _, actions = run(core, ["PS", "OPTIONS"], 0.0)
    assert actions == ["toggle_pause"] and core.paused
    run(core, [], 0.1)
    assert not run(core, ["CROSS"], 0.2)[0].targets


def test_axis_step_overrides():
    p = default_profile()
    p["macros"] = [macro(trigger=["CROSS"], steps=[
        {"type": "axis", "axis": "LX", "value": -1}, {"type": "wait", "ms": 40}, {"type": "release_all"}])]
    core = EngineCore(p)
    assert run(core, ["CROSS"], 0.0)[0].axes["LX"] == -1
    assert run(core, [], 0.05)[0].axes["LX"] == 0


def test_recording():
    core = EngineCore(default_profile())
    run(core, [], 0.0)
    core.start_recording(0.0)
    run(core, ["CROSS"], 0.1)
    run(core, [], 0.15)
    run(core, ["SQUARE"], 0.3)
    steps = core.stop_recording(0.4)
    assert steps[0] == {"type": "wait", "ms": 100}
    assert steps[1] == {"type": "tap", "targets": ["pad:CROSS"], "ms": 50}
    assert steps[-1] == {"type": "tap", "targets": ["pad:SQUARE"], "ms": 100}


def test_jitter_and_compact():
    import random
    m = normalize_profile({"macros": [macro(jitter_ms=10, steps=[{"type": "wait", "ms": 100}])]})["macros"][0]
    inst = MacroInstance(m, 0.0, rng=random.Random(1))
    inst.update(0.0)
    assert 0.09 <= inst.next_time <= 0.11
    s = compact_steps([{"type": "wait", "ms": 5}, {"type": "wait", "ms": 5}])
    assert s == [{"type": "wait", "ms": 10}]


def test_normalize_handles_garbage():
    p = normalize_profile({"name": "x", "macros": [{"name": "a", "mode": "zzz", "trigger": ["NOPE", "CROSS"]},
                                                    {"name": "a"}], "buttons": {"CROSS": ""}})
    assert p["macros"][0]["mode"] == "press" and p["macros"][0]["trigger"] == ["CROSS"]
    assert p["macros"][1]["name"] == "a (2)"
    assert p["buttons"]["CROSS"] == "none"


def test_threaded_engine_end_to_end():
    import time
    from remapper.engine import Engine
    from remapper.input_backend import _empty_state

    class FakeInput:
        def __init__(self):
            self.t0 = time.perf_counter()

        def poll(self):
            st = _empty_state()
            st["connected"] = True
            st["name"] = "Fake DualSense"
            st["buttons"]["CROSS"] = 0.05 < time.perf_counter() - self.t0 < 0.15
            return st

        def close(self):
            pass

    class Recorder:
        def __init__(self):
            self.seen = set()

        def describe(self):
            return "rec"

        def apply(self, out, kind):
            self.seen |= out.targets

        def close(self):
            pass

    rec = Recorder()
    p = default_profile()
    p["buttons"]["CROSS"] = "key:space"
    eng = Engine(FakeInput, lambda: rec, tick_hz=500, log=lambda m: None)
    eng.set_profile(p)
    eng.start()
    eng.send("record_start")
    time.sleep(0.3)
    eng.send("record_stop")
    time.sleep(0.05)
    snap = eng.snapshot()
    eng.stop()
    assert snap["connected"] and snap["device"] == "Fake DualSense"
    assert "key:space" in rec.seen
    kinds = []
    while not eng.events.empty():
        kinds.append(eng.events.get())
    recorded = [d for k, d in kinds if k == "recorded"][0]
    assert any(s["type"] == "tap" and s["targets"] == ["key:space"] for s in recorded)


def test_engine_process_demo():
    import time
    from remapper.engine_process import EngineProcess
    ep = EngineProcess({"demo": True, "controller_map": {}, "device_index": 0, "virtual_pad": False,
                        "keyboard_mouse": False, "mode": "rapide", "profile": default_profile()})
    ep.start()
    try:
        snap = {}
        deadline = time.time() + 15
        while time.time() < deadline and not snap.get("stats", {}).get("hz"):
            time.sleep(0.1)
            snap = ep.snapshot()
        assert ep.alive()
        assert snap["stats"]["hz"] > 500
        ep.send("pause", True)
        time.sleep(0.2)
        assert ep.snapshot()["paused"]
    finally:
        ep.stop()
    assert not ep.alive()


def test_keyboard_mouse_triggers():
    p = default_profile()
    p["macros"] = [
        macro(name="F", trigger=["key:f"], steps=[{"type": "tap", "targets": ["pad:CROSS"], "ms": 50}]),
        macro(name="X1", trigger=["mouse:x1"], mode="toggle", repeat=0,
              steps=[{"type": "tap", "targets": ["mouse:left"], "ms": 10}, {"type": "wait", "ms": 10}]),
        macro(name="Mix", trigger=["L1", "key:shift"], steps=[{"type": "tap", "targets": ["key:e"], "ms": 50}]),
    ]
    core = EngineCore(p)
    assert core.kbm_needed
    assert ("key:f",) in core.kbm_block and ("L1", "key:shift") in core.kbm_block
    out, _ = core.process({}, AX0, 0.0, kbm={"key:f"})
    assert "pad:CROSS" in out.targets
    assert "key:f" not in out.targets          # la touche physique n'est jamais renvoyée
    core.process({}, AX0, 0.1, kbm={"mouse:x1"})
    assert "X1" in core.running
    core.process({}, AX0, 0.2)
    core.process({}, AX0, 0.3, kbm={"mouse:x1"})
    assert "X1" not in core.running
    out, _ = core.process({"L1": True}, AX0, 1.0, kbm={"key:shift"})
    assert "key:e" in out.targets and "pad:L1" not in out.targets


def test_kbm_hotkey_and_no_listen_when_unused():
    p = default_profile()
    p["hotkeys"]["toggle_pause"] = ["key:f8"]
    core = EngineCore(p)
    _, actions = core.process({}, AX0, 0.0, kbm={"key:f8"})
    assert actions == ["toggle_pause"] and core.paused
    assert not EngineCore(default_profile()).kbm_needed


def test_mouse_move_step_instant_and_glide():
    p = default_profile()
    p["macros"] = [macro(trigger=["CROSS"], steps=[
        {"type": "mouse_move", "dx": 30, "dy": -10, "ms": 0},
        {"type": "mouse_move", "dx": 0, "dy": 100, "ms": 100},
    ])]
    core = EngineCore(p)
    out, _ = core.process({"CROSS": True}, AX0, 0.0)
    assert out.mouse == (30, -10)
    total = 0.0
    t = 0.0
    while t < 0.2:
        t += 0.001
        total += core.process({}, AX0, t)[0].mouse[1]
    assert abs(total - 100) < 1e-6
    assert not core.running


def test_record_keyboard_and_strip_stop_click():
    core = EngineCore(default_profile())
    core.process({}, AX0, 0.0)
    core.start_recording(0.0)
    core.process({}, AX0, 0.1, kbm={"key:a"})
    core.process({}, AX0, 0.15)
    core.process({}, AX0, 0.5, kbm={"mouse:left"})   # clic sur « Arrêter »
    steps = core.stop_recording(0.55)
    assert steps == [{"type": "wait", "ms": 100}, {"type": "tap", "targets": ["key:a"], "ms": 50}]


def test_normalize_kbm_trigger():
    p = normalize_profile({"macros": [{"name": "a", "trigger": ["key:f", "key:nope", "mouse:x2", "CROSS",
                                                                "wheel:up", "key:f"]}]})
    assert p["macros"][0]["trigger"] == ["key:f", "mouse:x2", "CROSS", "wheel:up"]


def test_device_choice_skips_virtual_pad():
    from remapper.input_backend import PygameInput
    inp = object.__new__(PygameInput)
    inp.wanted_name = ""
    choose = inp._choose
    assert choose(["Xbox 360 Controller", "DualSense Wireless Controller"]) == 1
    assert choose(["Controller (Xbox 360 For Windows)", "Steam Virtual Gamepad", "PS5 Controller"]) == 2
    assert choose(["Xbox 360 Controller", "Wireless Controller"]) == 1          # DS4 / DualSense en DInput
    assert choose(["Xbox 360 Controller", "8BitDo Pro 2"]) == 1                  # pas de Sony : pas la virtuelle
    assert choose(["Xbox 360 Controller"]) == 0
    inp.wanted_name = "8BitDo Pro 2"
    assert choose(["DualSense Wireless Controller", "8BitDo Pro 2"]) == 1       # choix manuel respecté


def test_macro_start_is_reported():
    p = default_profile()
    p["macros"] = [macro(name="Hado", trigger=["CROSS"], steps=[{"type": "tap", "targets": ["pad:SQUARE"], "ms": 30}])]
    core = EngineCore(p)
    core.process({"CROSS": True}, AX0, 0.0)
    assert core.started == ["Hado"]
