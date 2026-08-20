using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace AudioTray
{
    /// <summary>
    /// Supplies the notification-area icons.
    ///
    /// The bundled .ico files hold a single 128x128 image, and letting the
    /// shell squash that into a 16x16 tray slot looks muddy. Each icon is
    /// resampled once, with a proper filter, at the size Windows actually
    /// asks for - which also gets it right on high-DPI displays.
    ///
    /// A matching .ico placed next to the executable wins over the embedded
    /// copy, so the icons can be swapped without rebuilding.
    /// </summary>
    internal static class IconLoader
    {
        static readonly Dictionary<string, Icon> Cache = new Dictionary<string, Icon>();
        static readonly List<IntPtr> OwnedHandles = new List<IntPtr>();

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool DestroyIcon(IntPtr handle);

        public static Icon Get(string name)
        {
            Icon cached;
            if (Cache.TryGetValue(name, out cached)) { return cached; }

            Icon icon = null;
            try
            {
                using (Icon source = Load(name))
                {
                    if (source != null) { icon = Resample(source, SystemInformation.SmallIconSize); }
                }
            }
            catch (Exception)
            {
                icon = null;
            }

            if (icon == null) { icon = SystemIcons.Application; }

            Cache[name] = icon;
            return icon;
        }

        static Icon Load(string name)
        {
            string beside = Path.Combine(AppInfo.Directory, name + ".ico");
            if (File.Exists(beside))
            {
                try { return new Icon(beside); }
                catch (Exception) { /* fall through to the embedded copy */ }
            }

            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream("AudioTray." + name + ".ico"))
            {
                if (stream == null) { return null; }
                return new Icon(stream);
            }
        }

        static Icon Resample(Icon source, Size size)
        {
            using (Bitmap canvas = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppArgb))
            {
                using (Graphics graphics = Graphics.FromImage(canvas))
                using (Bitmap original = source.ToBitmap())
                {
                    graphics.Clear(Color.Transparent);
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.SmoothingMode = SmoothingMode.HighQuality;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    graphics.CompositingQuality = CompositingQuality.HighQuality;
                    graphics.DrawImage(original, new Rectangle(0, 0, size.Width, size.Height));
                }

                // FromHandle does not take ownership, so the handle is kept and
                // released in Dispose rather than left to leak.
                IntPtr handle = canvas.GetHicon();
                OwnedHandles.Add(handle);
                return Icon.FromHandle(handle);
            }
        }

        public static void Dispose()
        {
            foreach (IntPtr handle in OwnedHandles)
            {
                try { DestroyIcon(handle); } catch (Exception) { }
            }
            OwnedHandles.Clear();
            Cache.Clear();
        }
    }
}
