--[[
Nettoyage Fond - plugin Lightroom Classic.
Ajoute un masque IA "Arrière-plan" sur toutes les photos sélectionnées
et y applique un lissage (texture, clarté, netteté, bruit, saturation, exposition).
]]

return {
	LrSdkVersion = 13.0,
	LrSdkMinimumVersion = 13.0,

	LrToolkitIdentifier = "com.nettoyagefond.lightroom",
	LrPluginName = "Nettoyage Fond",

	-- Fichier > Modules externes (Plug-in Extras) : disponible dans tous les modules.
	LrExportMenuItems = {
		{
			title = "Lisser l'arrière-plan des photos sélectionnées...",
			file = "CleanBackground.lua",
		},
	},

	-- Bibliothèque > Modules externes (Plug-in Extras).
	LrLibraryMenuItems = {
		{
			title = "Lisser l'arrière-plan des photos sélectionnées...",
			file = "CleanBackground.lua",
		},
	},

	VERSION = { major = 1, minor = 0, revision = 0, build = 1 },
}
