using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace AudioTray
{
    internal enum Glyph { Microphone, MicrophoneMuted, Speaker, Headphones }

    /// <summary>
    /// Produces the notification-area icons.
    ///
    /// The defaults are drawn rather than loaded, for one reason: a fixed image
    /// cannot be legible on both a dark and a light taskbar. Drawing them means
    /// the ink colour follows the Windows theme, and it also means they are
    /// rendered at whatever size the shell asks for instead of being squashed
    /// down from a 128x128 bitmap.
    ///
    /// Anything the user picks wins over all of that.
    /// </summary>
    internal static class IconFactory
    {
        static readonly Dictionary<string, Icon> Cache = new Dictionary<string, Icon>();
        static readonly List<IntPtr> OwnedHandles = new List<IntPtr>();
        static bool _darkTaskbar = true;

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool DestroyIcon(IntPtr handle);

        static IconFactory() { RefreshTheme(); }

        /// <summary>
        /// Re-reads the taskbar theme. Returns true when it changed, which
        /// means every cached icon is now the wrong colour and must be rebuilt.
        /// </summary>
        public static bool RefreshTheme()
        {
            bool dark = true;
            try
            {
                object value = Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                    "SystemUsesLightTheme", null);
                if (value is int) { dark = ((int)value) == 0; }
            }
            catch (Exception) { }

            if (dark == _darkTaskbar) { return false; }

            _darkTaskbar = dark;
            Clear();
            return true;
        }

        public static Icon Microphone(bool muted)
        {
            // A mic-on.ico / mic-off.ico beside the executable still wins.
            string custom = Path.Combine(AppInfo.Directory, muted ? "mic-off.ico" : "mic-on.ico");
            if (File.Exists(custom))
            {
                Icon fromFile = FromFile(custom);
                if (fromFile != null) { return fromFile; }
            }

            return Drawn(muted ? Glyph.MicrophoneMuted : Glyph.Microphone);
        }

        public static Icon Output(string deviceName, string customIconPath)
        {
            if (!string.IsNullOrEmpty(customIconPath))
            {
                Icon chosen = FromFile(customIconPath);
                if (chosen != null) { return chosen; }
            }

            return Drawn(GuessGlyph(deviceName));
        }

        /// <summary>
        /// Picks a speaker or a headphone glyph from the device name, so the
        /// two devices being swapped between usually look different without
        /// anyone having to configure anything.
        /// </summary>
        static Glyph GuessGlyph(string deviceName)
        {
            if (string.IsNullOrEmpty(deviceName)) { return Glyph.Speaker; }

            string name = deviceName.ToLowerInvariant();
            string[] wornOnHead =
            {
                "headphone", "headset", "earphone", "earbud", "earpiece", "buds", "airpod",
                "hands-free", "handsfree",
                "kopfh",      // Kopfhörer, with or without the umlaut surviving
                "ohrh",       // Ohrhörer
                "casque", "auricular", "cuffie"
            };

            foreach (string word in wornOnHead)
            {
                if (name.Contains(word)) { return Glyph.Headphones; }
            }

            return Glyph.Speaker;
        }

        // --- files ----------------------------------------------------------

        static Icon FromFile(string path)
        {
            string key = "file:" + path.ToLowerInvariant() + ":" + (_darkTaskbar ? "d" : "l");

            Icon cached;
            if (Cache.TryGetValue(key, out cached)) { return cached; }

            Icon result = null;
            try
            {
                Size size = SystemInformation.SmallIconSize;

                if (path.EndsWith(".ico", StringComparison.OrdinalIgnoreCase))
                {
                    using (Icon source = new Icon(path))
                    using (Bitmap bitmap = source.ToBitmap())
                    {
                        result = Rasterise(bitmap, size);
                    }
                }
                else
                {
                    // PNG and friends, so a picked icon does not have to be .ico.
                    using (Image image = Image.FromFile(path))
                    using (Bitmap bitmap = new Bitmap(image))
                    {
                        result = Rasterise(bitmap, size);
                    }
                }
            }
            catch (Exception)
            {
                result = null;
            }

            if (result != null) { Cache[key] = result; }
            return result;
        }

        static Icon Rasterise(Bitmap source, Size size)
        {
            using (Bitmap canvas = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppArgb))
            {
                using (Graphics graphics = Graphics.FromImage(canvas))
                {
                    graphics.Clear(Color.Transparent);
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.SmoothingMode = SmoothingMode.HighQuality;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    graphics.CompositingQuality = CompositingQuality.HighQuality;
                    graphics.DrawImage(source, new Rectangle(0, 0, size.Width, size.Height));
                }
                return Own(canvas.GetHicon());
            }
        }

        // --- drawing --------------------------------------------------------

        static Icon Drawn(Glyph glyph)
        {
            string key = "glyph:" + glyph + ":" + (_darkTaskbar ? "d" : "l");

            Icon cached;
            if (Cache.TryGetValue(key, out cached)) { return cached; }

            Icon result;
            try { result = Render(glyph); }
            catch (Exception) { result = SystemIcons.Application; }

            Cache[key] = result;
            return result;
        }

        static Icon Render(Glyph glyph)
        {
            Size size = SystemInformation.SmallIconSize;

            // Drawn large and scaled down: GDI+ antialiasing at 16px directly
            // gives ragged curves, whereas supersampling stays crisp.
            const int Supersample = 8;
            int large = Math.Max(size.Width, size.Height) * Supersample;

            using (Bitmap big = new Bitmap(large, large, PixelFormat.Format32bppArgb))
            {
                using (Graphics graphics = Graphics.FromImage(big))
                {
                    graphics.Clear(Color.Transparent);
                    graphics.SmoothingMode = SmoothingMode.AntiAlias;

                    Color ink = _darkTaskbar
                              ? Color.FromArgb(248, 248, 248)
                              : Color.FromArgb(28, 28, 28);

                    switch (glyph)
                    {
                        case Glyph.Microphone:      DrawMicrophone(graphics, large, ink, false); break;
                        case Glyph.MicrophoneMuted: DrawMicrophone(graphics, large, ink, true);  break;
                        case Glyph.Headphones:      DrawHeadphones(graphics, large, ink);        break;
                        default:                    DrawSpeaker(graphics, large, ink);           break;
                    }
                }

                return Rasterise(big, size);
            }
        }

        static RectangleF Box(int extent, float x, float y, float width, float height)
        {
            return new RectangleF(x * extent, y * extent, width * extent, height * extent);
        }

        static Pen Stroke(Color colour, int extent, float width)
        {
            Pen pen = new Pen(colour, width * extent);
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            return pen;
        }

        static void DrawMicrophone(Graphics graphics, int extent, Color ink, bool muted)
        {
            // Dimmed while muted so the state reads even in a monochrome tray,
            // rather than relying on the slash colour alone.
            Color body = muted ? Color.FromArgb(150, ink) : ink;

            using (GraphicsPath capsule = new GraphicsPath())
            using (SolidBrush brush = new SolidBrush(body))
            using (Pen pen = Stroke(body, extent, 0.075f))
            {
                RectangleF head = Box(extent, 0.365f, 0.10f, 0.27f, 0.46f);
                float radius = head.Width;

                capsule.AddArc(head.Left, head.Top, radius, radius, 180, 180);
                capsule.AddArc(head.Left, head.Bottom - radius, radius, radius, 0, 180);
                capsule.CloseFigure();
                graphics.FillPath(brush, capsule);

                // Cradle, stem and base.
                graphics.DrawArc(pen, Box(extent, 0.26f, 0.34f, 0.48f, 0.40f), 0, 180);
                graphics.DrawLine(pen, 0.50f * extent, 0.74f * extent, 0.50f * extent, 0.86f * extent);
                graphics.DrawLine(pen, 0.33f * extent, 0.88f * extent, 0.67f * extent, 0.88f * extent);
            }

            if (!muted) { return; }

            // The halo is the taskbar's own colour, cutting a gap around the
            // slash so it stays legible where it crosses the microphone.
            Color halo = _darkTaskbar ? Color.FromArgb(24, 24, 24) : Color.FromArgb(244, 244, 244);
            using (Pen gap = Stroke(halo, extent, 0.20f))
            using (Pen slash = Stroke(Color.FromArgb(235, 70, 70), extent, 0.115f))
            {
                graphics.DrawLine(gap, 0.17f * extent, 0.15f * extent, 0.83f * extent, 0.85f * extent);
                graphics.DrawLine(slash, 0.17f * extent, 0.15f * extent, 0.83f * extent, 0.85f * extent);
            }
        }

        static void DrawSpeaker(Graphics graphics, int extent, Color ink)
        {
            using (SolidBrush brush = new SolidBrush(ink))
            using (Pen pen = Stroke(ink, extent, 0.075f))
            {
                PointF[] cone =
                {
                    new PointF(0.12f * extent, 0.38f * extent),
                    new PointF(0.28f * extent, 0.38f * extent),
                    new PointF(0.48f * extent, 0.17f * extent),
                    new PointF(0.48f * extent, 0.83f * extent),
                    new PointF(0.28f * extent, 0.62f * extent),
                    new PointF(0.12f * extent, 0.62f * extent)
                };
                graphics.FillPolygon(brush, cone);

                graphics.DrawArc(pen, Box(extent, 0.40f, 0.32f, 0.30f, 0.36f), -55, 110);
                graphics.DrawArc(pen, Box(extent, 0.40f, 0.20f, 0.48f, 0.60f), -50, 100);
            }
        }

        static void DrawHeadphones(Graphics graphics, int extent, Color ink)
        {
            using (SolidBrush brush = new SolidBrush(ink))
            using (Pen pen = Stroke(ink, extent, 0.10f))
            {
                graphics.DrawArc(pen, Box(extent, 0.15f, 0.14f, 0.70f, 0.70f), 180, 180);

                float cupWidth = 0.20f;
                float cupHeight = 0.34f;
                RectangleF left = Box(extent, 0.11f, 0.47f, cupWidth, cupHeight);
                RectangleF right = Box(extent, 0.69f, 0.47f, cupWidth, cupHeight);

                using (GraphicsPath path = new GraphicsPath())
                {
                    float radius = left.Width * 0.75f;
                    AddRounded(path, left, radius);
                    AddRounded(path, right, radius);
                    graphics.FillPath(brush, path);
                }
            }
        }

        static void AddRounded(GraphicsPath path, RectangleF rectangle, float radius)
        {
            path.StartFigure();
            path.AddArc(rectangle.Left, rectangle.Top, radius, radius, 180, 90);
            path.AddArc(rectangle.Right - radius, rectangle.Top, radius, radius, 270, 90);
            path.AddArc(rectangle.Right - radius, rectangle.Bottom - radius, radius, radius, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - radius, radius, radius, 90, 90);
            path.CloseFigure();
        }

        // --- lifetime -------------------------------------------------------

        static Icon Own(IntPtr handle)
        {
            OwnedHandles.Add(handle);
            return Icon.FromHandle(handle);
        }

        static void Clear()
        {
            Cache.Clear();
            foreach (IntPtr handle in OwnedHandles)
            {
                try { DestroyIcon(handle); } catch (Exception) { }
            }
            OwnedHandles.Clear();
        }

        /// <summary>Drops cached icons so the next request rebuilds them.</summary>
        public static void Invalidate() { Clear(); }

        public static void Dispose() { Clear(); }
    }
}
