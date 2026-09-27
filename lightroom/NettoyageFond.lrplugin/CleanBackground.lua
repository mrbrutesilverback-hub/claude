--[[
Pour chaque photo sélectionnée :
  1. l'affiche dans le module Développement,
  2. crée un masque IA "Sélectionner l'arrière-plan" (recalculé pour chaque photo),
  3. applique les réglages locaux choisis dans la boîte de dialogue.
]]

local LrApplication = import "LrApplication"
local LrApplicationView = import "LrApplicationView"
local LrBinding = import "LrBinding"
local LrDevelopController = import "LrDevelopController"
local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrPrefs = import "LrPrefs"
local LrProgressScope = import "LrProgressScope"
local LrTasks = import "LrTasks"
local LrView = import "LrView"

local prefs = LrPrefs.prefsForPlugin()

-- Type / sous-type du masque IA passé à LrDevelopController.createNewMask.
local MASK_TYPE = "aiSelection"
local MASK_SUBTYPE = "background"

-- Réglages locaux appliqués au masque, dans l'ordre d'affichage.
local ADJUSTMENTS = {
	{ key = "exposure",   param = "local_Exposure",       label = "Exposition",         min = -2,   max = 2,   default = 0.3,  digits = 2 },
	{ key = "texture",    param = "local_Texture",        label = "Texture",            min = -100, max = 100, default = -100, digits = 0 },
	{ key = "clarity",    param = "local_Clarity",        label = "Clarté",             min = -100, max = 100, default = -100, digits = 0 },
	{ key = "sharpness",  param = "local_Sharpness",      label = "Netteté",            min = -100, max = 100, default = -100, digits = 0 },
	{ key = "noise",      param = "local_LuminanceNoise", label = "Réduction du bruit", min = -100, max = 100, default = 80,   digits = 0 },
	{ key = "saturation", param = "local_Saturation",     label = "Saturation",         min = -100, max = 100, default = -40,  digits = 0 },
}

local OTHER_DEFAULTS = {
	passes = 1,   -- nombre de masques identiques empilés (2 = effet doublé)
	delay = 2.0,  -- secondes laissées à l'IA pour calculer le masque
}

local function prefOr(key, default)
	local value = prefs[key]
	if value == nil then return default end
	return value
end

local function showDialog(context)
	local f = LrView.osFactory()
	local props = LrBinding.makePropertyTable(context)

	for _, a in ipairs(ADJUSTMENTS) do
		props[a.key] = prefOr(a.key, a.default)
	end
	for key, default in pairs(OTHER_DEFAULTS) do
		props[key] = prefOr(key, default)
	end

	local rows = {}
	for _, a in ipairs(ADJUSTMENTS) do
		rows[#rows + 1] = f:row {
			f:static_text { title = a.label, width = LrView.share "label_width", alignment = "right" },
			f:slider { value = LrView.bind(a.key), min = a.min, max = a.max, integral = (a.digits == 0), width = 220 },
			f:edit_field { value = LrView.bind(a.key), min = a.min, max = a.max, precision = a.digits, width_in_digits = 6 },
		}
	end

	rows[#rows + 1] = f:separator { fill_horizontal = 1 }
	rows[#rows + 1] = f:row {
		f:static_text { title = "Nombre de passes", width = LrView.share "label_width", alignment = "right" },
		f:popup_menu {
			value = LrView.bind "passes",
			items = {
				{ title = "1 masque", value = 1 },
				{ title = "2 masques (effet doublé)", value = 2 },
			},
		},
	}
	rows[#rows + 1] = f:row {
		f:static_text { title = "Attente IA (s)", width = LrView.share "label_width", alignment = "right" },
		f:slider { value = LrView.bind "delay", min = 0.5, max = 8, width = 220 },
		f:edit_field { value = LrView.bind "delay", min = 0.5, max = 8, precision = 1, width_in_digits = 6 },
	}
	rows[#rows + 1] = f:static_text {
		title = "Augmentez l'attente si certains masques sont vides (ordinateur lent / gros fichiers).",
	}

	rows.bind_to_object = props
	rows.spacing = f:control_spacing()

	local result = LrDialogs.presentModalDialog {
		title = "Nettoyage Fond - lisser l'arrière-plan",
		contents = f:column(rows),
		actionVerb = "Appliquer",
	}
	if result ~= "ok" then return nil end

	local settings = {}
	for _, a in ipairs(ADJUSTMENTS) do
		settings[a.key] = props[a.key]
		prefs[a.key] = props[a.key]
	end
	for key in pairs(OTHER_DEFAULTS) do
		settings[key] = props[key]
		prefs[key] = props[key]
	end
	return settings
end

-- Attend que Lightroom affiche la photo demandée dans le Développement.
local function waitForPhoto(catalog, photo, timeout)
	local waited = 0
	while waited < timeout do
		if catalog:getTargetPhoto() == photo then return true end
		LrTasks.sleep(0.1)
		waited = waited + 0.1
	end
	return false
end

local function processPhoto(settings, failedParams)
	pcall(LrDevelopController.selectTool, "masking")

	for _ = 1, settings.passes do
		local ok, err = pcall(LrDevelopController.createNewMask, MASK_TYPE, MASK_SUBTYPE)
		if not ok then
			return false, "création du masque impossible : " .. tostring(err)
		end
		LrTasks.sleep(settings.delay)

		for _, a in ipairs(ADJUSTMENTS) do
			local setOk = pcall(LrDevelopController.setValue, a.param, settings[a.key])
			if not setOk then failedParams[a.param] = true end
		end
	end

	pcall(LrDevelopController.selectTool, "loupe")
	return true
end

local function run(context)
	if not LrDevelopController.createNewMask then
		LrDialogs.message("Nettoyage Fond",
			"Cette version de Lightroom Classic ne permet pas aux plugins de créer des masques.\n"
			.. "Mettez Lightroom Classic à jour (version 13 ou plus récente).", "critical")
		return
	end

	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()
	if #photos == 0 then
		LrDialogs.message("Nettoyage Fond", "Sélectionnez d'abord les photos à traiter.", "info")
		return
	end

	local settings = showDialog(context)
	if not settings then return end

	local originalActive = catalog:getTargetPhoto() or photos[1]

	LrApplicationView.switchToModule("develop")
	LrTasks.sleep(0.5)

	local progress = LrProgressScope {
		title = "Nettoyage Fond : lissage de " .. #photos .. " photo(s)",
		functionContext = context,
	}

	local done, errors, failedParams = 0, {}, {}

	for i, photo in ipairs(photos) do
		if progress:isCanceled() then break end
		progress:setPortionComplete(i - 1, #photos)
		progress:setCaption(photo:getFormattedMetadata("fileName") or ("Photo " .. i))

		catalog:setSelectedPhotos(photo, {})
		if not waitForPhoto(catalog, photo, 10) then
			errors[#errors + 1] = (photo:getFormattedMetadata("fileName") or "?") .. " : photo non chargée"
		else
			LrTasks.sleep(0.5) -- laisse le Développement finir de charger l'image
			local ok, err = processPhoto(settings, failedParams)
			if ok then
				done = done + 1
			else
				errors[#errors + 1] = (photo:getFormattedMetadata("fileName") or "?") .. " : " .. err
				if i == 1 then break end -- l'API ne fonctionne pas : inutile de continuer
			end
		end
	end

	progress:done()
	catalog:setSelectedPhotos(originalActive, photos)

	local message = done .. " / " .. #photos .. " photo(s) traitée(s)."
	local failedList = {}
	for param in pairs(failedParams) do failedList[#failedList + 1] = param end
	if #failedList > 0 then
		message = message .. "\n\nRéglages non appliqués : " .. table.concat(failedList, ", ")
	end
	if #errors > 0 then
		message = message .. "\n\nErreurs :\n" .. table.concat(errors, "\n", 1, math.min(#errors, 10))
	end
	LrDialogs.message("Nettoyage Fond", message, (#errors > 0) and "warning" or "info")
end

LrTasks.startAsyncTask(function()
	LrFunctionContext.callWithContext("NettoyageFond", function(context)
		LrDialogs.attachErrorDialogToFunctionContext(context)
		run(context)
	end)
end)
