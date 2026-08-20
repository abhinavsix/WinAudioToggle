using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace AudioTray
{
    internal static class AppInfo
    {
        public const string Title = "Audio Tray";

        public static string ExecutablePath
        {
            get { return Assembly.GetExecutingAssembly().Location; }
        }

        public static string Directory
        {
            get { return Path.GetDirectoryName(ExecutablePath); }
        }

        /// <summary>
        /// The order left-clicking the output icon cycles through.
        ///
        /// A docked laptop can expose five endpoints when only two are ever
        /// wanted, so an outputs.txt beside the executable narrows the
        /// rotation: one name fragment per line, in cycle order. Entries that
        /// match nothing plugged in right now are skipped, so one file works
        /// docked and undocked. Fewer than two matches falls back to every
        /// device, by name.
        /// </summary>
        public static AudioDevice[] GetRotation(AudioDevice[] devices)
        {
            string path = Path.Combine(Directory, "outputs.txt");

            if (File.Exists(path))
            {
                List<AudioDevice> ordered = new List<AudioDevice>();
                string[] lines;

                try { lines = File.ReadAllLines(path); }
                catch (IOException) { lines = new string[0]; }

                foreach (string line in lines)
                {
                    string pattern = line.Trim();
                    if (pattern.Length == 0 || pattern.StartsWith("#")) { continue; }

                    foreach (AudioDevice device in devices)
                    {
                        bool matches = device.Name.IndexOf(pattern, StringComparison.CurrentCultureIgnoreCase) >= 0;
                        if (matches && !ordered.Contains(device))
                        {
                            ordered.Add(device);
                            break;
                        }
                    }
                }

                if (ordered.Count >= 2) { return ordered.ToArray(); }
            }

            List<AudioDevice> all = new List<AudioDevice>(devices);
            all.Sort(delegate(AudioDevice a, AudioDevice b)
            {
                return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            });
            return all.ToArray();
        }
    }
}
