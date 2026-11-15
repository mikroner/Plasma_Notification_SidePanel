**Side Notification Panel**

Linux - KDE Plasma 6 only

A notification history that lives and slides out of the edge of your screen.

A small handle stays visible on a screen edge. Click it (or an icon in the system tray) and a drawer opens, attached to the edge, with all your notifications. The handle shows how many are unread, which apps they came from, and can blink when a new one arrives.

Everything is delivered by one self-contained script, install.sh. The widget is embedded in it.
An updater is integrated in the app.

Features
Notification drawer attached flush to the screen edge, with the handle drawn on top of it
Rich notifications: images, clickable links, action buttons, inline reply, "Show more" for long text
Grouping by application or by date, with collapsible sections
Search (Ctrl+F) and swipe to dismiss
Do Not Disturb: for 1 hour, until tomorrow, or until you turn it off
Plasma pop-ups on or off, while notifications still collect in the panel
History: a history button at the top of the panel shows everything received in the last N days (1 to 365), grouped by day and searchable. It survives Clear All and restarts
The handle shows the number of unread (or all) notifications, a bell, the icons of the apps with unread notifications, custom colours, and optional blinking
System tray icon that opens the same drawer
Updates from GitHub releases: checks automatically or on demand and offers to install in the background. No GitHub account is needed
Configurable opening: click only, or hover with a delay; close when the pointer leaves; drawer width and height
A Readme page in the settings window, with "What's new" for the current release

Chrome and other apps that send notifications through the standard desktop notification service appear here too (a Chrome web app shows up under "Google Chrome").

Requirements
KDE Plasma 6 (kpackagetool6, plasmashell)
A terminal running inside your Plasma session
For the system tray icon: the Qt Labs Platform QML module (some distributions package it separately; the rest of the widget works without it)
For ./install.sh test: gdbus (package glib2 / libglib2.0-bin)
Install

Download install.sh, make it executable and run it:

Example:

chmod +x install.sh
./install.sh

A simple menu offers install, update, uninstall and test notification functionality. You can also run them directly:

bash
./install.sh install                 # install the widget and create its panel
./install.sh update                  # update the widget; your panel and settings are kept
./install.sh uninstall               # remove the panel, the widget and the package
./install.sh test                    # send sample notifications (links, images, actions, reply)
Install options
Option	Meaning	Default
--edge left|right|top|bottom	screen edge for the panel	right
--mode handle|sidebar	handle: slim always-visible strip that opens a drawer. sidebar: wide auto-hiding panel	handle
--screen N	screen number, starting at 0	0
--size PX	panel thickness in pixels	handle 20, sidebar 360
--length PX	handle length in pixels	160
--recreate	build the panel again from scratch (resets its settings)	off
--no-restart	do not restart the Plasma shell after updating	off

If a panel with the widget already exists, install and update keep it and never change your settings. Options added in a newer version start at their defaults. Use --recreate only if you want a fresh panel.

Example: handle on the left edge, 30 px thick:

bash
./install.sh install --edge left --size 30
Pre-selected settings
Opens when you click the handle (or the tray icon)
The panel is attached to the screen edge, with the handle on top of it
The handle shows the number of unread notifications (a bell when none)
The handle blinks a few times when a new notification arrives
Notifications are grouped by application
Plasma's own pop-ups stay on
Icons of apps with unread notifications show on the handle (up to 5, then "+N")
A history is kept for 30 days
Configuration

Right-click the handle, then Configure. After an install or update the settings window opens once on the Readme page.

General
Option	What it does
Group notifications	By date, by application, or not grouped
Lines before "Show more"	How many lines of a long message are shown before it is folded
Relative times	"5 min ago" instead of the clock time
Mark as read on hover	Notifications count as read once you hover the open panel
Pop-ups	Turns Plasma's own pop-up for each new notification on or off (see the note below)
Keep a history	Remember notifications, also after Clear All and restarts
Keep for	How many days back the history is kept (1 to 365)
Opening
Option	What it does
Opened panel	Drawer attached to the screen edge, or a Plasma popup next to the handle
System tray	Also open the panel from a tray icon
Open the panel by	Clicking the handle, or hovering it (after a delay) or clicking
Delay before opening	How long the pointer must rest on the handle (hover mode)
Close when the pointer leaves	Closes a panel that was opened by hovering
Delay before closing	How long the pointer must be away
Width and height	Size of the opened panel
Handle
Option	What it does
Handle shows	The number (a bell when none), a bell and the number, or only a bell
The number counts	New (unread) notifications, or all notifications
Application icons	Icons of apps with unread notifications, at most a chosen number; the rest show as "+N". A longer handle fits more
Colours	Follow the Plasma theme, or custom colours for the normal and new-notification states
Blinking	Never, a few times, or until you open the panel
Updates
Option	What it does
GitHub repository	Where releases are looked up, as owner/repository
Look for a new version	About once a day
Install without asking	Download and install a found update by itself (Plasma still has to be restarted to use it)
Check for updates	Check now (press OK or Apply); also in the right-click menu of the handle
Notes
Pop-ups off works by holding Plasma's notifications back, the same way as Do Not Disturb. Notification sounds are silenced too, and critical notifications may still pop up if Plasma is set to allow that in Do Not Disturb mode.
History keeps text only (title, text, app, icon, time), not images or action buttons, up to 1500 entries. It only records notifications that arrive while the widget is running. It is stored in the widget's own settings.
Do Not Disturb set in this widget is tracked by this widget; it does not follow a Do Not Disturb turned on in Plasma's own panel.
In a wide auto-hiding sidebar panel, Plasma itself controls when the panel appears, so the opening options do not apply.
Updates

The app can update itself from the releases of a public GitHub repository. No GitHub account or login is needed. A check only asks api.github.com for the latest release, and an update downloads that release's .plasmoid file and installs it, keeping your settings.

When a newer version is found, a banner at the top of the panel offers Update. After installing, Restart Plasma (offered in the banner) loads the new version.

Updates run code from the repository, so only use a repository you trust.

Publishing a release (for the maintainer)
Set the repository once, either by editing GITHUB_REPO at the top of install.sh or with --repo:
bash
./install.sh package --repo yourname/yourrepo
Build the release file. This creates com.user.sidenotifications-<version>.plasmoid:
bash
./install.sh package
Create a GitHub release tagged v<version> (for example v2.2.0) and attach that file:
bash
gh release create v2.2.0 com.user.sidenotifications-2.2.0.plasmoid --title "2.2.0" --notes "What is new..."

The version in the tag must be higher than the installed one for the app to offer it. The release must be public.

Troubleshooting
The tray icon does not show: set it to "Always shown" in the system tray's settings. It needs the Qt Labs Platform QML module.
Nothing appears after installing: run ./install.sh from a terminal inside your Plasma session so it can reach the shell.
Try it out: ./install.sh test sends sample notifications.
Reset a broken panel: ./install.sh install --recreate.
Uninstall
bash
./install.sh uninstall
License

GPL-2.0-or-later
