--[[
	ClientSignals - petit bus d'événements entre les contrôleurs clients (Movement, UI, Animation, Effects).
	Chaque LocalScript qui require ce module obtient la même table (cache de require par environnement client).

	Signaux :
		Dash(cooldown)            le joueur local vient de dasher
		Slide(active)             début / fin du slide local
		MobileAction(name)        bouton tactile pressé ("Dash" | "Slide")
		Shake(intensity, time)    secousse caméra
		LocalCapture(victimName)  le joueur local vient de prendre une queue
]]

local Signals = {}
local events: { [string]: BindableEvent } = {}

local function get(name: string): BindableEvent
	local e = events[name]
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = name
		events[name] = e
	end
	return e
end

function Signals.Fire(name: string, ...)
	get(name):Fire(...)
end

function Signals.Connect(name: string, fn: (...any) -> ()): RBXScriptConnection
	return get(name).Event:Connect(fn)
end

-- état partagé lisible par tous les contrôleurs
Signals.State = {
	DashReadyAt = 0,
	DashCooldown = 0,
	Sliding = false,
}

return Signals
