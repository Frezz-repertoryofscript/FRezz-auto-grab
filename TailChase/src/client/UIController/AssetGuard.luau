--[[
	AssetGuard - vérifie que toutes les images de l'UI se chargent (ContentProvider:PreloadAsync).
	Une image qui échoue (asset retiré / hors vente / modéré) est remplacée par une icône de secours du même kit,
	et son ID est listé une seule fois dans l'Output : "[AssetGuard] image indisponible : rbxassetid://...".
	Les textures décoratives (studs, soleil) qui échouent sont simplement masquées.
]]

local ContentProvider = game:GetService("ContentProvider")

local AssetGuard = {}

local DECOR = { Studs = true, Soleil = true, Reflets = true }

function AssetGuard.Run(ctx, roots: { Instance })
	local Icons = ctx.Icons
	local fallbacks = {
		Icons.Get("Main/Star/Golden Star 1st Outline"),
		Icons.Get("Item/Gift/Red Gift 1st Outline"),
	}
	local byId: { [string]: { GuiObject } } = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" then
				byId[d.Image] = byId[d.Image] or {}
				table.insert(byId[d.Image], d)
			end
		end
	end
	local ids = {}
	for id in byId do table.insert(ids, id) end
	task.spawn(function()
		local failed = {}
		pcall(function()
			ContentProvider:PreloadAsync(ids, function(id, status)
				if status == Enum.AssetFetchStatus.Failure then table.insert(failed, id) end
			end)
		end)
		for _, id in failed do
			warn("[AssetGuard] image indisponible : " .. id)
			for _, img in byId[id] or {} do
				if DECOR[img.Name] then
					img.Visible = false
				else
					local fb = if id == fallbacks[1] then fallbacks[2] else fallbacks[1]
					img.Image = fb
				end
			end
		end
	end)
end

return AssetGuard
