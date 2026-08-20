using System;
using System.IO;
using System.Reflection;

namespace AudioTray
{
    /// <summary>
    /// Start-with-Windows, implemented as a shortcut in the user's own Startup
    /// folder.
    ///
    /// A HKCU\...\Run registry value would be fewer lines, but the Startup
    /// folder is the gentler option: it needs no registry write, the user can
    /// see and delete it in Explorer, and security software treats a Run key
    /// with much more suspicion than a shortcut.
    ///
    /// The shortcut is written through WScript.Shell by late binding, which
    /// avoids taking a COM interop assembly reference just to set six
    /// properties.
    /// </summary>
    internal static class AutoStart
    {
        static string ShortcutPath
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),
                                    AppInfo.Title + ".lnk");
            }
        }

        public static bool IsEnabled
        {
            get
            {
                try { return File.Exists(ShortcutPath); }
                catch (Exception) { return false; }
            }
        }

        /// <summary>Returns null on success, or a message describing what went wrong.</summary>
        public static string SetEnabled(bool enabled)
        {
            try
            {
                if (!enabled)
                {
                    if (File.Exists(ShortcutPath)) { File.Delete(ShortcutPath); }
                    return null;
                }

                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) { return "Windows Script Host is not available on this PC."; }

                object shell = Activator.CreateInstance(shellType);
                object shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                                         null, shell, new object[] { ShortcutPath });
                Type shortcutType = shortcut.GetType();

                Set(shortcutType, shortcut, "TargetPath", AppInfo.ExecutablePath);
                Set(shortcutType, shortcut, "WorkingDirectory", AppInfo.Directory);
                Set(shortcutType, shortcut, "Description", "Microphone and audio output tray icons");
                Set(shortcutType, shortcut, "IconLocation", AppInfo.ExecutablePath + ",0");

                shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
                return null;
            }
            catch (Exception error)
            {
                return error.Message;
            }
        }

        static void Set(Type type, object target, string property, object value)
        {
            type.InvokeMember(property, BindingFlags.SetProperty, null, target, new object[] { value });
        }
    }
}
