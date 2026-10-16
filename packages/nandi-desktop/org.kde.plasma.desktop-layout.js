// Nandi OS first-login layout: one bottom panel with the Loop Eyes head and
// the whitelist tray in place of the stock system tray.
var panel = new Panel
panel.location = "bottom"
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2)

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["Shortcuts"]
kickoff.writeConfig("global", "Alt+F1")

panel.addWidget("org.kde.plasma.pager")
panel.addWidget("org.kde.plasma.icontasks")
panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.loop.eyes.panel")
panel.addWidget("org.kde.plasma.whitelisttray")
panel.addWidget("org.kde.plasma.digitalclock")
panel.addWidget("org.kde.plasma.showdesktop")

var desktops = desktopsForActivity(currentActivity())
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.kde.image"
}
