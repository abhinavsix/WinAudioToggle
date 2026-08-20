using System;
using System.Globalization;
using System.Threading;
using System.Windows.Forms;

namespace AudioTray
{
    internal static class Program
    {
        const string MutexName = "Local\\WinAudioToggle.AudioTray";

        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // Ahead of the single-instance check on purpose. The report is
            // read-only, and it is wanted precisely when the tray is already
            // running - taking the mutex first would answer "already running"
            // at the one moment the report is being asked for.
            if (HasFlag(args, "--diagnose"))
            {
                string report = Diagnostics.Build();
                string savedTo = Diagnostics.Save(report);
                if (savedTo != null) { report += Environment.NewLine + "Saved to: " + savedTo; }
                MessageBox.Show(report, AppInfo.Title + " diagnostics",
                                MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }

            // Local\ rather than Global\: one instance per signed-in user, so
            // two people on the same PC each get their own tray icons.
            bool createdNew;
            using (Mutex instanceLock = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show("Audio Tray is already running.\n\nLook for the icons in the notification area.",
                                    AppInfo.Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }

                int poll = ReadPollInterval(args);

                try
                {
                    using (TrayContext context = new TrayContext(poll))
                    {
                        Application.Run(context);
                    }
                }
                catch (Exception error)
                {
                    // There is no console to print to, so say it out loud
                    // rather than vanishing without explanation.
                    MessageBox.Show("Audio Tray could not start.\n\n" + error.Message,
                                    AppInfo.Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
                finally
                {
                    try { instanceLock.ReleaseMutex(); } catch (Exception) { }
                }
            }

            return 0;
        }

        static bool HasFlag(string[] args, string flag)
        {
            foreach (string arg in args)
            {
                if (arg.Equals(flag, StringComparison.OrdinalIgnoreCase)) { return true; }
            }
            return false;
        }

        /// <summary>Accepts "--poll 500"; anything unparseable falls back to the default.</summary>
        static int ReadPollInterval(string[] args)
        {
            const int defaultPoll = 1000;

            for (int i = 0; i < args.Length - 1; i++)
            {
                if (!args[i].Equals("--poll", StringComparison.OrdinalIgnoreCase)) { continue; }

                int value;
                if (int.TryParse(args[i + 1], NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
                    && value >= 250 && value <= 10000)
                {
                    return value;
                }
            }

            return defaultPoll;
        }
    }
}
