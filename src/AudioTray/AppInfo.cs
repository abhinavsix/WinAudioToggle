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

    }
}
