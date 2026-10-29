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
clock.writeConfig("customDateFormat", "MM-dd ddd")
clock.writeConfig("dateFormat", "custom")
clock.writeConfig("fontWeight", 400)
clock.writeConfig("use24hFormat", 2)

panel.addWidget("org.kde.plasma.showdesktop")

// Desktop background. The openSUSE look-and-feel loads this template and only
// then forces wallpaperPlugin = org.kde.image, and a same-value assignment is a
// no-op, so the keys written here survive. Naming the image explicitly keeps
// provisioning out of the distribution's own files under /usr/share, which a
// package update would restore anyway.
var wallpaper = "/usr/local/share/jan-wallpaper.jpg"
// Scope this the same way the look-and-feel layout that loads this template
// does, so re-running it cannot reach another activity's desktops.
var desktopsArray = desktopsForActivity(currentActivity())
for (var i = 0; i < desktopsArray.length; i++) {
    desktopsArray[i].wallpaperPlugin = "org.kde.image"
    desktopsArray[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]
    desktopsArray[i].writeConfig("Image", wallpaper)
    desktopsArray[i].writeConfig("FillMode", 2)
    // org.kde.image defaults Color to #ffffff; keep the Sweet-dark background
    // so an unreadable image leaves a dark desktop rather than a white one.
    desktopsArray[i].writeConfig("Color", "0,0,0")
}
