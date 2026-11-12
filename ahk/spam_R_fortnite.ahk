; =====================================================================
;  SPAM R — Fortnite (AutoHotkey v2)
;  Maintiens R  -> R est spammé le plus vite possible (timing précis à la µs)
;
;  F8          activer / désactiver le spam
;  F9 / F10    plus lent / plus rapide
;  F11         Fortnite seulement <-> partout
;  Ctrl+Échap  quitter le script
;
;  Vitesse : règle-la sur ton FPS. Un appui doit durer au moins 1 image,
;  sinon le jeu le rate. 240 FPS = ~4 ms par image -> 4 ms appuyé + 4 ms relâché.
; =====================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
#MaxThreadsPerHotkey 1
A_HotkeyInterval := 0
A_MaxHotkeysPerInterval := 1000
ProcessSetPriority "High"
SendMode "Input"
SetKeyDelay -1, -1

DllCall("winmm\timeBeginPeriod", "UInt", 1)      ; timer Windows à 1 ms
OnExit (*) => DllCall("winmm\timeEndPeriod", "UInt", 1)

global Enabled      := true
global DownMs       := 4      ; durée appuyé (ms)
global UpMs         := 4      ; durée relâché (ms)
global FortniteOnly := true   ; spam seulement quand Fortnite est au premier plan
global SC_R         := "sc013" ; touche R physique (même place en AZERTY et QWERTY)

ShowTip("Spam R prêt : " Speed())

; ---------------------------------------------------------------- spam
#HotIf Enabled && InGame()
*$r::
{
    while GetKeyState("r", "P") {
        Send "{Blind}{" SC_R " down}"
        PreciseSleep(DownMs)
        Send "{Blind}{" SC_R " up}"
        PreciseSleep(UpMs)
    }
}
#HotIf

; ------------------------------------------------------------- réglages
F8:: {
    global Enabled
    Enabled := !Enabled
    SoundBeep Enabled ? 1200 : 600, 60
    ShowTip("Spam R : " (Enabled ? "ACTIVÉ" : "désactivé"))
}
F9::  ChangeSpeed(+1)
F10:: ChangeSpeed(-1)
F11:: {
    global FortniteOnly
    FortniteOnly := !FortniteOnly
    ShowTip(FortniteOnly ? "Seulement dans Fortnite" : "Partout")
}
^Esc:: ExitApp

; ------------------------------------------------------------ fonctions
InGame() {
    return !FortniteOnly || WinActive("ahk_exe FortniteClient-Win64-Shipping.exe")
}

ChangeSpeed(step) {
    global DownMs, UpMs
    DownMs := Max(1, Min(50, DownMs + step))
    UpMs   := Max(1, Min(50, UpMs + step))
    ShowTip(Speed())
}

Speed() {
    return DownMs "+" UpMs " ms  ≈ " Round(1000 / (DownMs + UpMs)) " appuis/s"
}

ShowTip(text) {
    ToolTip text
    SetTimer () => ToolTip(), -1500
}

; Attente précise : Sleep pour le gros du délai, puis attente active (QPC) pour la fin.
PreciseSleep(ms) {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    start := 0
    DllCall("QueryPerformanceCounter", "Int64*", &start)
    target := start + ms * freq / 1000
    if (ms > 2)
        Sleep ms - 2
    now := 0
    loop {
        DllCall("QueryPerformanceCounter", "Int64*", &now)
    } until now >= target
}
