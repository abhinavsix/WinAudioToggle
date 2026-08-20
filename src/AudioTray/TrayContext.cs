using System;
using System.Drawing;
using System.Windows.Forms;

namespace AudioTray
{
    /// <summary>
    /// The two notification-area icons and everything hanging off them.
    /// </summary>
    internal sealed class TrayContext : ApplicationContext
    {
        const int TooltipLimit = 63;   // NotifyIcon.Text throws above this

        readonly NotifyIcon _micIcon = new NotifyIcon();
        readonly NotifyIcon _outIcon = new NotifyIcon();
        readonly ContextMenuStrip _micMenu = new ContextMenuStrip();
        readonly ContextMenuStrip _outMenu = new ContextMenuStrip();
        readonly Timer _timer = new Timer();

        // What is currently painted, so the icons are only touched on a change.
        string _shownMicId;
        bool? _shownMicMuted;
        string _shownOutId;
        int _consecutiveFailures;
        bool _reportedFailure;

        public TrayContext(int pollMilliseconds)
        {
            _micIcon.Icon = IconFactory.Microphone(false);
            _micIcon.Text = "Microphone";
            _micIcon.ContextMenuStrip = _micMenu;
            _micIcon.Visible = true;
            _micIcon.MouseClick += OnMicClick;

            _outIcon.Icon = IconFactory.Output("", null);
            _outIcon.Text = "Audio output";
            _outIcon.ContextMenuStrip = _outMenu;
            _outIcon.Visible = true;
            _outIcon.MouseClick += OnOutputClick;

            _micMenu.Opening += BuildMicMenu;
            _outMenu.Opening += BuildOutputMenu;

            _timer.Interval = pollMilliseconds;
            _timer.Tick += OnTick;

            // Deliberately tolerant: when this is launched from the Startup
            // folder it can beat the Windows audio service to being ready, and
            // dying at that point would mean failing on every single boot. Show
            // the icons regardless and let the timer pick the state up.
            try { Refresh(); }
            catch (Exception) { }

            _timer.Start();
        }

        // --- painting -------------------------------------------------------

        void SetTooltip(NotifyIcon icon, string text)
        {
            if (text.Length > TooltipLimit) { text = text.Substring(0, TooltipLimit - 3) + "..."; }
            icon.Text = text;
        }

        /// <summary>
        /// Re-reads the current state and repaints only what moved. Called on
        /// the timer and immediately after any action taken here, so a click
        /// feels instant instead of waiting for the next tick.
        /// </summary>
        void Refresh()
        {
            AudioStatus status = Audio.GetStatus();

            if (status.HasInput)
            {
                if (_shownMicMuted != status.InputMuted)
                {
                    _micIcon.Icon = IconFactory.Microphone(status.InputMuted);
                }
                if (_shownMicId != status.InputId || _shownMicMuted != status.InputMuted)
                {
                    SetTooltip(_micIcon, "Mic (" + (status.InputMuted ? "Muted" : "Live") + "): " + status.InputName);
                }
                _shownMicId = status.InputId;
                _shownMicMuted = status.InputMuted;
            }
            else if (_shownMicId != "<none>")
            {
                _micIcon.Icon = IconFactory.Microphone(true);
                SetTooltip(_micIcon, "No microphone connected");
                _shownMicId = "<none>";
                _shownMicMuted = null;
            }

            if (status.HasOutput)
            {
                if (_shownOutId != status.OutputId)
                {
                    _outIcon.Icon = IconFactory.Output(status.OutputName,
                                                       Favorites.IconFor(status.OutputName));
                    SetTooltip(_outIcon, "Output: " + status.OutputName);
                    _shownOutId = status.OutputId;
                }
            }
            else if (_shownOutId != "<none>")
            {
                SetTooltip(_outIcon, "No audio output connected");
                _shownOutId = "<none>";
            }
        }

        void Notify(NotifyIcon icon, string message)
        {
            try { icon.ShowBalloonTip(4000, AppInfo.Title, message, ToolTipIcon.Info); }
            catch (Exception) { }
        }

        // --- actions --------------------------------------------------------

        void OnMicClick(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) { return; }   // right-click opens the menu
            ToggleMute();
        }

        void OnOutputClick(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) { return; }
            CycleOutput();
        }

        void ToggleMute()
        {
            try
            {
                AudioStatus status = Audio.GetStatus();
                if (!status.HasInput)
                {
                    Notify(_micIcon, "No microphone is connected.");
                    return;
                }

                Audio.SetCaptureMute(!status.InputMuted, false);
                Refresh();
            }
            catch (Exception error)
            {
                Notify(_micIcon, error.Message);
            }
        }

        void CycleOutput()
        {
            try
            {
                AudioDevice[] devices = Audio.ListDevices(false);
                if (devices.Length < 2)
                {
                    Notify(_outIcon, "Only one output device is active.");
                    return;
                }

                AudioDevice[] rotation = Favorites.Rotation(devices);

                int current = -1;
                for (int i = 0; i < rotation.Length; i++)
                {
                    if (rotation[i].IsDefault) { current = i; break; }
                }

                // A default sitting outside the rotation drops in at the top.
                AudioDevice target = (current < 0) ? rotation[0] : rotation[(current + 1) % rotation.Length];

                Audio.SetDefaultDevice(target.Id);
                Refresh();
            }
            catch (Exception error)
            {
                NotifySwitchFailure(error);
            }
        }

        /// <summary>
        /// A refused switch is the one failure worth explaining properly:
        /// PolicyConfig is undocumented, so a balloon alone leaves nothing to
        /// act on. Point at the report that carries the actual status codes.
        /// </summary>
        void NotifySwitchFailure(Exception error)
        {
            Notify(_outIcon, error.Message
                   + "  (right-click this icon and choose Diagnostics for details)");
        }

        void ShowFavorites()
        {
            try
            {
                using (FavoritesForm form = new FavoritesForm(Audio.ListDevices(false)))
                {
                    // The tray owns no window, so nothing would bring this to
                    // the front on its own.
                    form.TopMost = true;
                    form.Shown += delegate { form.TopMost = false; form.Activate(); };

                    if (form.ShowDialog() != DialogResult.OK) { return; }
                }

                RepaintEverything();
            }
            catch (Exception error)
            {
                MessageBox.Show("Could not open favourites: " + error.Message,
                                AppInfo.Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        /// <summary>Forces both icons to be rebuilt on the next refresh.</summary>
        void RepaintEverything()
        {
            IconFactory.Invalidate();
            _shownOutId = null;
            _shownMicId = null;
            _shownMicMuted = null;

            try { Refresh(); } catch (Exception) { }
        }

        void ShowDiagnostics()
        {
            try
            {
                string report = Diagnostics.Build();
                string savedTo = Diagnostics.Save(report);

                string body = report;
                if (savedTo != null) { body += Environment.NewLine + "Saved to: " + savedTo; }

                // Ctrl+C on a MessageBox copies its text, which makes this easy
                // to paste somewhere useful.
                MessageBox.Show(body, AppInfo.Title + " diagnostics",
                                MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception failure)
            {
                MessageBox.Show("Could not build the report: " + failure.Message,
                                AppInfo.Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        void SelectDevice(string deviceId, NotifyIcon icon)
        {
            try
            {
                Audio.SetDefaultDevice(deviceId);
                Refresh();
            }
            catch (Exception error)
            {
                NotifySwitchFailure(error);
            }
        }

        void ToggleBluetooth(BluetoothAudioDevice device)
        {
            try
            {
                bool connect = !device.Connected;
                if (!Bluetooth.BeginSetConnected(device.Address, connect, device.Name))
                {
                    Notify(_outIcon, "Still working on the previous Bluetooth request.");
                    return;
                }

                Notify(_outIcon, (connect ? "Connecting to " : "Disconnecting ") + device.Name + "...");
            }
            catch (Exception error)
            {
                Notify(_outIcon, error.Message);
            }
        }

        // --- menus ----------------------------------------------------------

        static ToolStripItem AddHeader(ToolStripItemCollection items, string text)
        {
            ToolStripItem item = items.Add(text);
            item.Enabled = false;
            return item;
        }

        void AddQuit(ToolStripItemCollection items)
        {
            items.Add(new ToolStripSeparator());
            ToolStripMenuItem quit = new ToolStripMenuItem("Quit " + AppInfo.Title);
            quit.Click += delegate { ExitThread(); };
            items.Add(quit);
        }

        void BuildMicMenu(object sender, System.ComponentModel.CancelEventArgs e)
        {
            _micMenu.Items.Clear();

            try
            {
                AudioStatus status = Audio.GetStatus();
                AddHeader(_micMenu.Items, "Microphone");

                ToolStripMenuItem muted = new ToolStripMenuItem("Muted");
                muted.Checked = status.InputMuted;
                muted.Enabled = status.HasInput;
                muted.Click += delegate { ToggleMute(); };
                _micMenu.Items.Add(muted);

                _micMenu.Items.Add(new ToolStripSeparator());
                AddHeader(_micMenu.Items, "Input device");

                foreach (AudioDevice device in Favorites.Rotation(Audio.ListDevices(true)))
                {
                    ToolStripMenuItem item = new ToolStripMenuItem(device.Name);
                    item.Checked = device.IsDefault;
                    string id = device.Id;
                    item.Click += delegate { SelectDevice(id, _micIcon); };
                    _micMenu.Items.Add(item);
                }
            }
            catch (Exception error)
            {
                AddHeader(_micMenu.Items, error.Message);
            }

            AddQuit(_micMenu.Items);
        }

        void BuildOutputMenu(object sender, System.ComponentModel.CancelEventArgs e)
        {
            _outMenu.Items.Clear();

            try
            {
                AddHeader(_outMenu.Items, "Output device");

                foreach (AudioDevice device in Favorites.Rotation(Audio.ListDevices(false)))
                {
                    ToolStripMenuItem item = new ToolStripMenuItem(device.Name);
                    item.Checked = device.IsDefault;
                    string id = device.Id;
                    item.Click += delegate { SelectDevice(id, _outIcon); };
                    _outMenu.Items.Add(item);
                }
            }
            catch (Exception error)
            {
                AddHeader(_outMenu.Items, error.Message);
            }

            _outMenu.Items.Add(new ToolStripSeparator());
            _outMenu.Items.Add(BuildBluetoothMenu());
            _outMenu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem sound = new ToolStripMenuItem("Windows sound settings...");
            sound.Click += delegate
            {
                try { System.Diagnostics.Process.Start("control.exe", "mmsys.cpl,,0"); }
                catch (Exception error) { Notify(_outIcon, error.Message); }
            };
            _outMenu.Items.Add(sound);

            ToolStripMenuItem favorites = new ToolStripMenuItem("Favourite outputs && icons...");
            favorites.Click += delegate { ShowFavorites(); };
            _outMenu.Items.Add(favorites);

            ToolStripMenuItem diagnostics = new ToolStripMenuItem("Diagnostics...");
            diagnostics.Click += delegate { ShowDiagnostics(); };
            _outMenu.Items.Add(diagnostics);

            ToolStripMenuItem autoStart = new ToolStripMenuItem("Start with Windows");
            autoStart.Checked = AutoStart.IsEnabled;
            autoStart.Click += delegate
            {
                string failure = AutoStart.SetEnabled(!AutoStart.IsEnabled);
                if (failure != null) { Notify(_outIcon, "Could not update autostart: " + failure); }
            };
            _outMenu.Items.Add(autoStart);

            AddQuit(_outMenu.Items);
        }

        ToolStripMenuItem BuildBluetoothMenu()
        {
            ToolStripMenuItem root = new ToolStripMenuItem("Bluetooth");

            try
            {
                if (!Bluetooth.HasRadio())
                {
                    AddHeader(root.DropDownItems, "No Bluetooth radio found");
                    return root;
                }

                BluetoothAudioDevice[] paired = Bluetooth.ListPaired(true);
                if (paired.Length == 0) { paired = Bluetooth.ListPaired(false); }

                if (paired.Length == 0)
                {
                    AddHeader(root.DropDownItems, "No paired devices");
                }
                else
                {
                    foreach (BluetoothAudioDevice device in paired)
                    {
                        string label = device.Connected ? device.Name + "  (connected)" : device.Name;
                        ToolStripMenuItem item = new ToolStripMenuItem(label);
                        item.Checked = device.Connected;
                        BluetoothAudioDevice target = device;
                        item.Click += delegate { ToggleBluetooth(target); };
                        root.DropDownItems.Add(item);
                    }
                }

                root.DropDownItems.Add(new ToolStripSeparator());
                AddHeader(root.DropDownItems, "Pair new devices in Windows Settings");
            }
            catch (Exception error)
            {
                AddHeader(root.DropDownItems, error.Message);
            }

            return root;
        }

        // --- timer ----------------------------------------------------------

        void OnTick(object sender, EventArgs e)
        {
            try
            {
                Refresh();
                _consecutiveFailures = 0;
                _reportedFailure = false;

                // A theme switch changes what colour the icons need to be.
                if (IconFactory.RefreshTheme()) { RepaintEverything(); }

                string bluetoothResult = Bluetooth.TakeResultMessage();
                if (bluetoothResult != null)
                {
                    Notify(_outIcon, bluetoothResult);
                    // Connecting changes which endpoints exist; force a repaint.
                    _shownOutId = null;
                }
            }
            catch (Exception error)
            {
                // Windows briefly refuses these calls while devices are being
                // re-enumerated. Never let that take the whole tray down, and
                // only complain if the state stays unreadable.
                _consecutiveFailures++;
                if (_consecutiveFailures >= 5 && !_reportedFailure)
                {
                    _reportedFailure = true;
                    Notify(_micIcon, "Audio state is unreadable: " + error.Message);
                }
            }
        }

        // --- shutdown -------------------------------------------------------

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                try { _timer.Stop(); _timer.Dispose(); } catch (Exception) { }

                // Without an explicit hide the icons linger in the tray as
                // ghosts until the user happens to hover over them.
                foreach (NotifyIcon icon in new[] { _micIcon, _outIcon })
                {
                    try { icon.Visible = false; icon.Dispose(); } catch (Exception) { }
                }

                try { _micMenu.Dispose(); _outMenu.Dispose(); } catch (Exception) { }
                    IconFactory.Dispose();
            }

            base.Dispose(disposing);
        }
    }
}
