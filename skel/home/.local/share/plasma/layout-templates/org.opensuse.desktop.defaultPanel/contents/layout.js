var panel = new Panel

panel.floating = false
panel.location = "top"
panel.height = 32

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["General"]
kickoff.writeConfig("icon", "start-here-branding")

panel.addWidget("org.kde.plasma.pager")

var tasks = panel.addWidget("org.kde.plasma.taskmanager")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig(
    "launchers",
    "preferred://filemanager,applications:org.kde.konsole.desktop"
)

panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.systemtray")

var clock = panel.addWidget("org.kde.plasma.digitalclock")
clock.currentConfigGroup = ["Appearance"]
clock.writeConfig("customDateFormat", "mm-dd ddd")
clock.writeConfig("dateFormat", "custom")
clock.writeConfig("fontWeight", 400)
clock.writeConfig("use24hFormat", 2)

panel.addWidget("org.kde.plasma.showdesktop")
