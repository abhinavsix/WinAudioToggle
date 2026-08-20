using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AudioTray
{
    internal sealed class FavoriteEntry
    {
        public string Pattern = "";
        public string IconPath = "";

        public bool Matches(AudioDevice device)
        {
            if (Pattern.Length == 0 || device == null) { return false; }
            return device.Name.IndexOf(Pattern, StringComparison.CurrentCultureIgnoreCase) >= 0;
        }
    }

    /// <summary>
    /// The outputs left-clicking cycles through, in order, each with an
    /// optional icon.
    ///
    /// Stored as plain text beside the executable so it can be edited by hand
    /// or copied between machines:
    ///
    ///     Headset = C:\icons\headset.png
    ///     Speakers
    ///
    /// Entries are matched as a case-insensitive substring of the device name,
    /// so a fragment is enough and one file works docked and undocked - names
    /// that match nothing plugged in right now are simply skipped.
    /// </summary>
    internal static class Favorites
    {
        const string FileName = "favorites.txt";
        const string LegacyFileName = "outputs.txt";

        public static string FilePath
        {
            get { return Path.Combine(AppInfo.Directory, FileName); }
        }

        static string ReadablePath()
        {
            if (File.Exists(FilePath)) { return FilePath; }

            // The earlier releases called it outputs.txt; keep reading it.
            string legacy = Path.Combine(AppInfo.Directory, LegacyFileName);
            return File.Exists(legacy) ? legacy : null;
        }

        public static List<FavoriteEntry> Load()
        {
            List<FavoriteEntry> entries = new List<FavoriteEntry>();

            string path = ReadablePath();
            if (path == null) { return entries; }

            string[] lines;
            try { lines = File.ReadAllLines(path); }
            catch (IOException) { return entries; }

            foreach (string raw in lines)
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) { continue; }

                FavoriteEntry entry = new FavoriteEntry();

                // Split on the first '=' only: device names may contain one,
                // icon paths almost never do.
                int separator = line.IndexOf('=');
                if (separator >= 0)
                {
                    entry.Pattern = line.Substring(0, separator).Trim();
                    entry.IconPath = line.Substring(separator + 1).Trim();
                }
                else
                {
                    entry.Pattern = line;
                }

                if (entry.Pattern.Length > 0) { entries.Add(entry); }
            }

            return entries;
        }

        /// <summary>Returns null on success, or a message describing the failure.</summary>
        public static string Save(List<FavoriteEntry> entries)
        {
            StringBuilder text = new StringBuilder();
            text.AppendLine("# Audio Tray favourites.");
            text.AppendLine("# The outputs that left-clicking the tray icon cycles through, in order.");
            text.AppendLine("#");
            text.AppendLine("#   <part of the device name> = <icon file>");
            text.AppendLine("#");
            text.AppendLine("# The icon is optional. Names are matched case-insensitively as a");
            text.AppendLine("# substring, and anything not plugged in right now is skipped.");
            text.AppendLine();

            foreach (FavoriteEntry entry in entries)
            {
                if (entry.Pattern.Trim().Length == 0) { continue; }

                text.Append(entry.Pattern.Trim());
                if (entry.IconPath.Trim().Length > 0)
                {
                    text.Append(" = ");
                    text.Append(entry.IconPath.Trim());
                }
                text.AppendLine();
            }

            try
            {
                File.WriteAllText(FilePath, text.ToString());
                return null;
            }
            catch (Exception error)
            {
                return error.Message;
            }
        }

        /// <summary>The custom icon for a device, or null if it has none.</summary>
        public static string IconFor(string deviceName)
        {
            if (string.IsNullOrEmpty(deviceName)) { return null; }

            AudioDevice probe = new AudioDevice();
            probe.Name = deviceName;

            foreach (FavoriteEntry entry in Load())
            {
                if (entry.Matches(probe) && entry.IconPath.Length > 0) { return entry.IconPath; }
            }

            return null;
        }

        /// <summary>
        /// The cycle order: favourites first, in the order they were saved.
        /// Falls back to every device by name when fewer than two favourites
        /// are actually present, so cycling never dead-ends.
        /// </summary>
        public static AudioDevice[] Rotation(AudioDevice[] devices)
        {
            List<AudioDevice> ordered = new List<AudioDevice>();

            foreach (FavoriteEntry entry in Load())
            {
                foreach (AudioDevice device in devices)
                {
                    if (entry.Matches(device) && !ordered.Contains(device))
                    {
                        ordered.Add(device);
                        break;
                    }
                }
            }

            if (ordered.Count >= 2) { return ordered.ToArray(); }

            List<AudioDevice> all = new List<AudioDevice>(devices);
            all.Sort(delegate(AudioDevice a, AudioDevice b)
            {
                return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            });
            return all.ToArray();
        }
    }
}
