# What's New

Everything that changed in **Side Notification Panel**, newest first.

> Versions 1.0.0 to 1.6 were developed step by step and were not numbered one by one, so they are
> summarised together at the end. From 2.0.0 on, every release is listed separately.

---

## 2.6.0
- **Folding groups.** When notifications are grouped by application, groups without unread notifications fold up and show their newest one or two notifications as a single line each. Groups with unread notifications stay open.
- When a folded group has more notifications than the lines shown, a line of dots (`. . . . . .`) follows them. Click it to open the group.
- Click a line or the group's header to open or fold a group. A folded group opens by itself when something new arrives, and groups you have just read fold up when the panel closes, so the list never jumps while you read.
- While you search, all groups are open so no match is hidden.
- New settings (General): fold up groups on or off, and how many lines (0 to 2) stay visible in a folded group.

## 2.5.1
- Group headers (when grouped by app) are tinted with the app's colour, 20% stronger than its cards.
- The icon colour is now the default for **Card colours** on new installs. A colour you chose yourself is kept.
- Fixed harmless warnings in the Plasma log caused by a value that briefly had no setting while the panel closed.

## 2.5.0
- **Card colours.** Notification cards and their edge bar can be tinted per app (General → Card colours):
  - none,
  - a steady colour made from the app's name,
  - the main colour of the app's icon (grey, black and white are ignored; those apps fall back to the name colour).
- The same colours are used in the history.

## 2.4.0
- **Built-in sound player.** Sounds are now played by the widget itself (Qt Multimedia), with no external program. The system commands (`paplay`, `pw-play`, …) are the fallback, or can be chosen under General → Sound → Player.
- With the built-in player, the warm-up plays the sound silently first, then again at full volume.

## 2.3.3
- The **Play sound** test button in the settings now plays immediately, without Apply, and shows which player was used or why it failed.
- `paplay` is tried first; `canberra-gtk-play` moved to last, because it can report success while staying silent.
- Default warm-up raised to 1000 ms.

## 2.3.2
- New **Warm-up** setting for sound: a moment of silence played first, so a sleeping sound card is awake when the sound starts.

## 2.3.1
- Built-in sounds are found in the installed sound themes (Ocean, freedesktop, Oxygen, your home folder).
- More players are tried; a failing sound now tells you why in the panel.
- Choosing **My own file…** opens a file browser, and there is a Browse button.

## 2.3.0
- **Sound on a new notification** (General → Sound), off by default: a choice of built-in sounds or your own file, and a button to try it.

## 2.2.1 (also built as 2.2)
- **About page:** link to the project website on GitHub, copyright "Mikroner" and the author linked to the GitHub profile.
- The release file made by `./install.sh package` no longer contains machine-specific details (user ID, timestamps).

## 2.2.0
- **Updates from GitHub releases.** The app checks for a new release about once a day, or on demand (right-click menu → *Check for updates*, or Configure → Updates). A banner at the top of the panel offers to download and install it in the background; your settings are kept. No GitHub account is needed for a public repository.
- Optional: install found updates without asking. Plasma still has to be restarted to start the new version, and the banner offers to do it.
- New **Updates** settings page (repository, daily check, install without asking, check now).
- New installer commands: `./install.sh package` builds the `.plasmoid` file to attach to a release, and `--repo owner/name` sets the repository.

## 2.1.3
- Fixed: long notifications in the history were cut off. They now have a **Show more / Show less** link.

## 2.1.2
- Fixed: notification text in the history showed raw markup (such as `<b>` tags). It now displays like in the main list.

## 2.1.1
- Version update only; the history gained no other changes in this release.

## 2.1.0
- **Notification history.** A history button at the top of the panel shows everything you received in the last N days, grouped by day. It survives *Clear All* and restarts.
- The history has its own **search box** (also searches the day names).
- History settings (General): on or off, and how many days to keep (1 to 365). History keeps text only, up to 1500 entries, and has a **Clear history** button with confirmation.
- Fixed: with a wider handle panel (for example 30 px), the handle no longer covers part of the notifications in the opened drawer.

## 2.0.0
- **Pop-ups on/off** (General): hide Plasma's own pop-up for new notifications while they still collect in the panel and the handle still counts and blinks. (It works by holding notifications back like Do Not Disturb, so sounds are silenced too.)
- **App icons on the handle:** the icons of apps with unread notifications, above and below the number, with "+N" for the ones that do not fit (up to a chosen maximum, default 5).
- **Do Not Disturb fixed.** It used a setting that does not exist in Plasma 6 and most likely never worked. It now uses Plasma's real "inhibited until" time, including the timed options.
- New **Readme** page in the settings, with a short description of the app, **What's new** for the release and a description of every option. The settings window opens once on it after an install or update.
- Updating keeps all your settings; options added later start at their defaults.

---

## 1.0.0 to 1.6

**Panel and notifications**
- Notification history sidebar for KDE Plasma 6, built as a widget.
- Rich cards: images, clickable links, action buttons, inline reply, and "Show more" for long text.
- Grouping by date or by application, with collapsible sections; search; swipe to dismiss; animations.
- Do Not Disturb with timers (for example one hour or until tomorrow), *Clear All* with confirmation.
- Notifications from Chrome web apps and other apps that use the standard desktop notification service appear too.

**Handle and drawer**
- A small always-visible handle on a screen edge opens the panel.
- The drawer is attached to the screen edge, with a copy of the handle drawn on top of it.
- Configurable opening: click only (the default) or hover with a delay, close when the pointer leaves, drawer width and height.
- The handle shows a number (a bell when there is none), counts unread or all notifications, can use custom colours, and blinks a few times, until opened, or never (default: a few times).
- Optional system tray icon that opens and closes the same drawer.

**Installer**
- One self-contained script, `install.sh`, with a menu (install, update, uninstall, test) and command-line options for the screen edge, mode, size and handle length.
- Updating keeps your existing panel and settings; `--recreate` builds the panel again from scratch.
- A note after install and update lists the pre-selected defaults and the other options.
- `./install.sh test` sends sample notifications (links, images, actions, reply, long text, different urgencies).

**Defaults chosen for you:** open by clicking the handle, blink a few times, show the number of unread notifications, group by application.
