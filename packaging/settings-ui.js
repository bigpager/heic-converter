#!/usr/bin/osascript -l JavaScript
//
// settings-ui.js — the heic-converter settings window.
//
// Run as:  osascript -l JavaScript settings-ui.js /path/to/heic-converter
//
// This drives real AppKit controls (NSSwitch, NSTextField, NSOpenPanel) through
// JavaScript for Automation's ObjC bridge. The alternative — a compiled SwiftUI
// app — would mean the .pkg payload stops being pure shell script and picks up a
// Mach-O binary, which drags in Developer ID *Application* signing, a hardened
// runtime, and an Xcode dependency at build time. None of that is currently
// needed. This gets a native window for the cost of a text file.
//
// All persistence goes back through the heic-converter CLI rather than touching
// config.conf directly, so validation, the $HOME expansion, and the agent
// rebuild after a folder change all stay in one place.

ObjC.import('Cocoa');

function run(argv) {
  // Launched from the .app there are no arguments, so fall back to the
  // installed location rather than dereferencing undefined.
  argv = argv || [];
  var CLI = argv[0] || '/usr/local/bin/heic-converter';

  var app = Application.currentApplication();
  app.includeStandardAdditions = true;

  // --- talking to the CLI ----------------------------------------------------

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  function cli(args) {
    try {
      return app.doShellScript(shellQuote(CLI) + ' ' + args);
    } catch (e) {
      return '';
    }
  }

  function readFormat()  { return cli('format') || 'both'; }
  function readQuality() { return cli('quality') || '90'; }
  function readFolder()  { return cli('watch-folder') || ''; }

  // Collapse the two switches back into the single value the config stores.
  // Both off is a legitimate state: 'none' leaves the agent installed and
  // watching, but producing nothing — conversion paused rather than uninstalled.
  function writeFormat(png, jpg) {
    var value = png && jpg ? 'both' : (png ? 'png' : (jpg ? 'jpg' : 'none'));
    cli('format ' + value);
  }

  // Display ~/… rather than the full path, matching how people think of it.
  function prettyPath(p) {
    var home = ObjC.unwrap($.NSHomeDirectory());
    if (p === home) return '~';
    if (p.indexOf(home + '/') === 0) return '~' + p.slice(home.length);
    return p;
  }

  // --- initial state ---------------------------------------------------------

  var format = readFormat();
  var pngOn = (format === 'png' || format === 'both');
  var jpgOn = (format === 'jpg' || format === 'both');
  var folder = readFolder();

  // --- window ----------------------------------------------------------------

  var W = 460, H = 310;
  var styleMask = $.NSWindowStyleMaskTitled | $.NSWindowStyleMaskClosable
                | $.NSWindowStyleMaskMiniaturizable;

  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, W, H), styleMask, $.NSBackingStoreBuffered, false);
  win.title = 'heic-converter';
  win.releasedWhenClosed = false;

  var content = win.contentView;

  function label(text, x, y, w, bold) {
    var l = $.NSTextField.labelWithString($(text));
    l.setFrame($.NSMakeRect(x, y, w, 20));
    if (bold) l.font = $.NSFont.boldSystemFontOfSize(13);
    content.addSubview(l);
    return l;
  }

  // Row 1 — PNG
  label('Convert to PNG', 28, H - 66, 200, false);
  var pngSwitch = $.NSSwitch.alloc.initWithFrame($.NSMakeRect(W - 90, H - 70, 50, 26));
  pngSwitch.state = pngOn ? $.NSControlStateValueOn : $.NSControlStateValueOff;
  content.addSubview(pngSwitch);

  // Row 2 — JPG
  label('Convert to JPG', 28, H - 116, 200, false);
  var jpgSwitch = $.NSSwitch.alloc.initWithFrame($.NSMakeRect(W - 90, H - 120, 50, 26));
  jpgSwitch.state = jpgOn ? $.NSControlStateValueOn : $.NSControlStateValueOff;
  content.addSubview(jpgSwitch);

  // Row 3 — quality, indented under JPG since it only applies to it
  var qualityLabel = label('Quality', 52, H - 154, 60, false);
  var qualityField = $.NSTextField.alloc.initWithFrame($.NSMakeRect(118, H - 157, 56, 24));
  qualityField.stringValue = readQuality();
  qualityField.alignment = $.NSTextAlignmentRight;
  content.addSubview(qualityField);
  var percentLabel = label('%', 180, H - 154, 20, false);

  var separator = $.NSBox.alloc.initWithFrame($.NSMakeRect(28, H - 186, W - 56, 1));
  separator.boxType = $.NSBoxSeparator;
  content.addSubview(separator);

  // Row 4 — watch folder
  label('Watch folder', 28, H - 216, 200, true);
  var pathLabel = label(prettyPath(folder), 28, H - 246, W - 160, false);
  pathLabel.lineBreakMode = $.NSLineBreakByTruncatingMiddle;
  pathLabel.textColor = $.NSColor.secondaryLabelColor;

  var browseButton = $.NSButton.buttonWithTitleTargetAction($('Browse…'), $(), null);
  browseButton.setFrame($.NSMakeRect(W - 122, H - 251, 94, 28));
  browseButton.bezelStyle = $.NSBezelStyleRounded;
  content.addSubview(browseButton);

  var pausedNotice = label('', 28, 26, 260, false);
  pausedNotice.textColor = $.NSColor.secondaryLabelColor;

  var doneButton = $.NSButton.buttonWithTitleTargetAction($('Done'), $(), null);
  doneButton.setFrame($.NSMakeRect(W - 108, 20, 80, 30));
  doneButton.bezelStyle = $.NSBezelStyleRounded;
  doneButton.keyEquivalent = '\r';
  content.addSubview(doneButton);

  // --- behaviour -------------------------------------------------------------

  // Both switches off is allowed; say so plainly so it doesn't look broken.
  function syncPausedNotice() {
    var off = pngSwitch.state === $.NSControlStateValueOff
           && jpgSwitch.state === $.NSControlStateValueOff;
    pausedNotice.stringValue = off ? 'Conversion paused — no output selected.' : '';
  }

  function syncQualityEnabled() {
    var on = jpgSwitch.state === $.NSControlStateValueOn;
    qualityField.enabled = on;
    qualityLabel.textColor = on ? $.NSColor.labelColor : $.NSColor.tertiaryLabelColor;
    percentLabel.textColor = on ? $.NSColor.labelColor : $.NSColor.tertiaryLabelColor;
  }

  function commitQuality() {
    var raw = ObjC.unwrap(qualityField.stringValue).trim();
    var n = parseInt(raw, 10);
    if (isNaN(n) || String(n) !== raw || n < 0 || n > 100) {
      // Reject silently rather than nagging: restore what's actually stored.
      qualityField.stringValue = readQuality();
      $.NSBeep();
      return;
    }
    cli('quality ' + n);
  }

  function commitFormat() {
    var png = pngSwitch.state === $.NSControlStateValueOn;
    var jpg = jpgSwitch.state === $.NSControlStateValueOn;
    writeFormat(png, jpg);
    syncQualityEnabled();
    syncPausedNotice();
  }

  ObjC.registerSubclass({
    name: 'HeicSettingsHandler',
    superclass: 'NSObject',
    methods: {
      'pngToggled:': {
        types: ['void', ['id']],
        implementation: function () { commitFormat(); }
      },
      'jpgToggled:': {
        types: ['void', ['id']],
        implementation: function () { commitFormat(); }
      },
      'qualityChanged:': {
        types: ['void', ['id']],
        implementation: function () { commitQuality(); }
      },
      'browseClicked:': {
        types: ['void', ['id']],
        implementation: function () {
          var panel = $.NSOpenPanel.openPanel;
          panel.canChooseFiles = false;
          panel.canChooseDirectories = true;
          panel.allowsMultipleSelection = false;
          panel.prompt = $('Watch This Folder');
          panel.message = $('Choose the folder to watch for new HEIC images.');
          if (folder) {
            panel.directoryURL = $.NSURL.fileURLWithPath($(folder));
          }
          if (panel.runModal === $.NSModalResponseOK) {
            var picked = ObjC.unwrap(panel.URL.path);
            // watch-folder also regenerates the agent, since launchd bakes the
            // path into WatchPaths.
            cli('watch-folder ' + shellQuote(picked));
            folder = readFolder();
            pathLabel.stringValue = prettyPath(folder);
          }
        }
      },
      'doneClicked:': {
        types: ['void', ['id']],
        implementation: function () {
          commitQuality();
          $.NSApp.terminate(null);
        }
      }
    }
  });

  var handler = $.HeicSettingsHandler.alloc.init;

  pngSwitch.target = handler;      pngSwitch.action = 'pngToggled:';
  jpgSwitch.target = handler;      jpgSwitch.action = 'jpgToggled:';
  qualityField.target = handler;   qualityField.action = 'qualityChanged:';
  browseButton.target = handler;   browseButton.action = 'browseClicked:';
  doneButton.target = handler;     doneButton.action = 'doneClicked:';

  syncQualityEnabled();
  syncPausedNotice();

  // --- show it ---------------------------------------------------------------

  var nsapp = $.NSApplication.sharedApplication;
  nsapp.setActivationPolicy($.NSApplicationActivationPolicyRegular);
  win.center;
  win.makeKeyAndOrderFront(null);
  nsapp.activateIgnoringOtherApps(true);

  // Only start a run loop if nothing else already has one. Under plain
  // osascript there is none; if this is ever hosted somewhere that already
  // runs NSApplication, calling run again would deadlock.
  if (!nsapp.isRunning) {
    nsapp.run;
  }
}
