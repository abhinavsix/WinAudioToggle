using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace AudioTray
{
    /// <summary>
    /// A one-shot report of what this machine actually supports.
    ///
    /// PolicyConfig is undocumented, so when a default-device switch is
    /// refused the HRESULT is the only evidence there is. This gathers it
    /// along with enough context to act on, without changing any setting:
    /// the switching test re-applies the device that is already default, so
    /// running it is harmless.
    /// </summary>
    internal static class Diagnostics
    {
        public static string Build()
        {
            StringBuilder report = new StringBuilder();

            report.AppendLine("Audio Tray diagnostics");
            report.AppendLine("Generated " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture));
            report.AppendLine();

            report.AppendLine("System");
            report.AppendLine("  Windows      : " + Environment.OSVersion.VersionString);
            report.AppendLine("  Process      : " + (IntPtr.Size == 8 ? "64-bit" : "32-bit")
                                                  + ", .NET " + Environment.Version);
            report.AppendLine("  Executable   : " + AppInfo.ExecutablePath);
            report.AppendLine();

            AudioStatus status = null;
            report.AppendLine("Core Audio");
            try
            {
                status = Audio.GetStatus();
                report.AppendLine("  Default out  : " + (status.HasOutput ? status.OutputName : "(none)"));
                report.AppendLine("     id        : " + (status.HasOutput ? status.OutputId : "-"));
                report.AppendLine("  Default in   : " + (status.HasInput ? status.InputName : "(none)"));
                report.AppendLine("     id        : " + (status.HasInput ? status.InputId : "-"));
                report.AppendLine("     muted     : " + (status.HasInput ? (status.InputMuted ? "yes" : "no") : "-"));
            }
            catch (Exception error)
            {
                report.AppendLine("  FAILED: " + error.Message);
            }

            try
            {
                report.AppendLine("  Outputs      : " + Audio.ListDevices(false).Length + " active");
                report.AppendLine("  Inputs       : " + Audio.ListDevices(true).Length + " active");
            }
            catch (Exception error)
            {
                report.AppendLine("  Enumeration FAILED: " + error.Message);
            }
            report.AppendLine();

            report.AppendLine("Default-device switching");
            try
            {
                string flavours = Audio.GetPolicyConfigFlavour();
                report.AppendLine("  QueryInterface matrix:");
                foreach (string line in (flavours ?? "").Split(';'))
                {
                    if (line.Trim().Length > 0) { report.AppendLine("    " + line.Trim()); }
                }
            }
            catch (Exception error)
            {
                report.AppendLine("  Interfaces   : probe failed - " + error.Message);
            }

            if (status != null && status.HasOutput)
            {
                try
                {
                    // Re-applying the device that is already default changes
                    // nothing, but exercises the exact call that fails.
                    string detail;
                    bool ok = Audio.TrySetDefaultDevice(status.OutputId, out detail);
                    report.AppendLine("  Test switch  : " + (ok ? "SUCCEEDED" : "FAILED"));
                    if (detail.Length > 0) { report.AppendLine("  Detail       : " + detail); }
                }
                catch (Exception error)
                {
                    report.AppendLine("  Test switch  : threw " + error.GetType().Name + " - " + error.Message);
                }
            }
            else
            {
                report.AppendLine("  Test switch  : skipped, no default output to re-apply");
            }
            report.AppendLine();

            report.AppendLine("Bluetooth");
            try
            {
                bool radio = Bluetooth.HasRadio();
                report.AppendLine("  Radio        : " + (radio ? "present" : "none found"));
                if (radio)
                {
                    BluetoothAudioDevice[] paired = Bluetooth.ListPaired(true);
                    bool audioOnly = paired.Length > 0;
                    if (!audioOnly) { paired = Bluetooth.ListPaired(false); }

                    report.AppendLine("  Paired       : " + paired.Length
                                      + (audioOnly ? " audio device(s)" : " device(s), none classed as audio"));
                    foreach (BluetoothAudioDevice device in paired)
                    {
                        report.AppendLine("    - " + device.Name + "  [" + device.AddressText + "]"
                                          + (device.Connected ? "  connected" : ""));
                    }
                }
            }
            catch (Exception error)
            {
                report.AppendLine("  FAILED: " + error.Message);
            }

            return report.ToString();
        }

        /// <summary>Writes the report next to the executable, falling back to TEMP.</summary>
        public static string Save(string report)
        {
            string[] candidates = new[]
            {
                Path.Combine(AppInfo.Directory, "AudioTray-diagnostics.txt"),
                Path.Combine(Path.GetTempPath(), "AudioTray-diagnostics.txt")
            };

            foreach (string path in candidates)
            {
                try
                {
                    File.WriteAllText(path, report);
                    return path;
                }
                catch (Exception) { }
            }

            return null;
        }
    }
}
