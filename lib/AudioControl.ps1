# AudioControl.ps1
# Shared library for the taskbar audio tools. Dot-source it; do not run it directly.
#
#   . "$PSScriptRoot\AudioControl.ps1"
#
# Talks to the Core Audio API that ships with Windows. No modules to install,
# nothing downloaded, no background process.

Set-StrictMode -Version 2.0

$script:AudioTypesLoaded = $false

function Initialize-AudioTypes {
    <#
        Compiles the interop layer once per process. Everything here is a
        Windows API - the only reason C# is involved at all is that the Core
        Audio interfaces are plain COM (not IDispatch), so PowerShell cannot
        call them without a typed wrapper.
    #>
    if ($script:AudioTypesLoaded) { return }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $refs = @(
        [System.Windows.Forms.Form].Assembly.Location
        [System.Drawing.Icon].Assembly.Location
    )

    $source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WinAudioToggle
{
    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        public Guid fmtid;
        public int pid;
        public PropertyKey(Guid id, int p) { fmtid = id; pid = p; }
    }

    // Only the header and one pointer-sized union member are read, but the
    // struct must still be at least as large as the real PROPVARIANT: both
    // IPropertyStore::GetValue and PropVariantClear write the full native size
    // (16 bytes on x86, 24 on x64) into this buffer. Undersizing it corrupts
    // the stack. 32 leaves room on both architectures.
    [StructLayout(LayoutKind.Explicit, Size = 32)]
    internal struct PropVariant
    {
        [FieldOffset(0)] public short vt;
        [FieldOffset(2)] public short wReserved1;
        [FieldOffset(4)] public short wReserved2;
        [FieldOffset(6)] public short wReserved3;
        [FieldOffset(8)] public IntPtr pointerValue;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice ppDevice);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr pClient);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int pcDevices);
        [PreserveSig] int Item(int nDevice, out IMMDevice ppDevice);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
                                   [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        [PreserveSig] int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
        [PreserveSig] int GetId(out IntPtr ppstrId);
        [PreserveSig] int GetState(out int pdwState);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int cProps);
        [PreserveSig] int GetAt(int iProp, out PropertyKey pkey);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant pv);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant pv);
        [PreserveSig] int Commit();
    }

    // Every method must be declared, in order, so the vtable offsets line up.
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr pNotify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr pNotify);
        [PreserveSig] int GetChannelCount(out int pnChannelCount);
        [PreserveSig] int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
        [PreserveSig] int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
        [PreserveSig] int GetMasterVolumeLevel(out float pfLevelDB);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float pfLevel);
        [PreserveSig] int SetChannelVolumeLevel(int nChannel, float fLevelDB, ref Guid pguidEventContext);
        [PreserveSig] int SetChannelVolumeLevelScalar(int nChannel, float fLevel, ref Guid pguidEventContext);
        [PreserveSig] int GetChannelVolumeLevel(int nChannel, out float pfLevelDB);
        [PreserveSig] int GetChannelVolumeLevelScalar(int nChannel, out float pfLevel);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
        [PreserveSig] int GetVolumeStepInfo(out int pnStep, out int pnStepCount);
        [PreserveSig] int VolumeStepUp(ref Guid pguidEventContext);
        [PreserveSig] int VolumeStepDown(ref Guid pguidEventContext);
        [PreserveSig] int QueryHardwareSupport(out int pdwHardwareSupportMask);
        [PreserveSig] int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
    }

    // Windows never shipped a public API for changing the default endpoint.
    // IPolicyConfig is the shell's own internal interface and has been stable
    // from Vista through Windows 11; it is what every audio switcher uses.
    // Unused methods are declared with pointer-sized placeholders because only
    // their slot position matters.
    [ComImport, Guid("f8679f50-850a-45de-be8b-c4348c9a0d0b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat(IntPtr a, IntPtr b);
        [PreserveSig] int GetDeviceFormat(IntPtr a, int b, IntPtr c);
        [PreserveSig] int ResetDeviceFormat(IntPtr a);
        [PreserveSig] int SetDeviceFormat(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int GetProcessingPeriod(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetProcessingPeriod(IntPtr a, IntPtr b);
        [PreserveSig] int GetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int SetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int GetPropertyValue(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetPropertyValue(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceId, ERole role);
        [PreserveSig] int SetEndpointVisibility(IntPtr a, int b);
    }

    // Same thing, minus ResetDeviceFormat, so SetDefaultEndpoint sits one slot
    // earlier. Some builds only answer to this IID.
    [ComImport, Guid("568b9108-44bf-40b4-9006-86afe5b5a620"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfigVista
    {
        [PreserveSig] int GetMixFormat(IntPtr a, IntPtr b);
        [PreserveSig] int GetDeviceFormat(IntPtr a, int b, IntPtr c);
        [PreserveSig] int SetDeviceFormat(IntPtr a, IntPtr b, IntPtr c);
        [PreserveSig] int GetProcessingPeriod(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetProcessingPeriod(IntPtr a, IntPtr b);
        [PreserveSig] int GetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int SetShareMode(IntPtr a, IntPtr b);
        [PreserveSig] int GetPropertyValue(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetPropertyValue(IntPtr a, int b, IntPtr c, IntPtr d);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceId, ERole role);
        [PreserveSig] int SetEndpointVisibility(IntPtr a, int b);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    internal class PolicyConfigClientComObject { }

    public class AudioDevice
    {
        public string Id;
        public string Name;
        public bool IsDefault;
        public override string ToString() { return Name; }
    }

    /// <summary>
    /// Everything the tray icons poll for, gathered in one pass so the timer
    /// costs three COM calls a second rather than a full device enumeration.
    /// </summary>
    public class AudioStatus
    {
        public string OutputId = "";
        public string OutputName = "";
        public bool HasOutput;
        public string InputId = "";
        public string InputName = "";
        public bool HasInput;
        public bool InputMuted;
    }

    public static class Audio
    {
        const int CLSCTX_ALL = 23;
        const int DEVICE_STATE_ACTIVE = 1;
        const int STGM_READ = 0;
        const short VT_LPWSTR = 31;

        static readonly Guid IID_IAudioEndpointVolume = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        static readonly PropertyKey PKEY_Device_FriendlyName =
            new PropertyKey(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 14);

        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant pvar);

        static IMMDeviceEnumerator CreateEnumerator()
        {
            return (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        }

        static string GetId(IMMDevice device)
        {
            IntPtr p;
            Marshal.ThrowExceptionForHR(device.GetId(out p));
            try { return Marshal.PtrToStringUni(p); }
            finally { Marshal.FreeCoTaskMem(p); }
        }

        static string GetFriendlyName(IMMDevice device)
        {
            IPropertyStore store;
            if (device.OpenPropertyStore(STGM_READ, out store) != 0) { return "(unnamed device)"; }

            PropertyKey key = PKEY_Device_FriendlyName;
            PropVariant value;
            if (store.GetValue(ref key, out value) != 0) { return "(unnamed device)"; }

            try
            {
                if (value.vt != VT_LPWSTR) { return "(unnamed device)"; }
                string name = Marshal.PtrToStringUni(value.pointerValue);
                return string.IsNullOrEmpty(name) ? "(unnamed device)" : name;
            }
            finally { PropVariantClear(ref value); }
        }

        static IAudioEndpointVolume GetEndpointVolume(IMMDevice device)
        {
            Guid iid = IID_IAudioEndpointVolume;
            object raw;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out raw));
            return (IAudioEndpointVolume)raw;
        }

        static IMMDevice GetDefaultDevice(EDataFlow flow, ERole role)
        {
            IMMDevice device;
            int hr = CreateEnumerator().GetDefaultAudioEndpoint(flow, role, out device);
            // 0x80070490 (ERROR_NOT_FOUND) just means nothing is plugged in.
            if (hr == unchecked((int)0x80070490)) { return null; }
            Marshal.ThrowExceptionForHR(hr);
            return device;
        }

        public static AudioDevice[] ListDevices(bool capture)
        {
            EDataFlow flow = capture ? EDataFlow.eCapture : EDataFlow.eRender;
            IMMDeviceEnumerator enumerator = CreateEnumerator();

            string defaultId = null;
            IMMDevice current = GetDefaultDevice(flow, ERole.eMultimedia);
            if (current != null) { defaultId = GetId(current); }

            IMMDeviceCollection collection;
            Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, out collection));

            int count;
            Marshal.ThrowExceptionForHR(collection.GetCount(out count));

            List<AudioDevice> devices = new List<AudioDevice>();
            for (int i = 0; i < count; i++)
            {
                IMMDevice device;
                if (collection.Item(i, out device) != 0) { continue; }
                string id = GetId(device);
                devices.Add(new AudioDevice
                {
                    Id = id,
                    Name = GetFriendlyName(device),
                    IsDefault = (id == defaultId)
                });
            }
            return devices.ToArray();
        }

        public static AudioDevice GetDefault(bool capture)
        {
            EDataFlow flow = capture ? EDataFlow.eCapture : EDataFlow.eRender;
            IMMDevice device = GetDefaultDevice(flow, ERole.eMultimedia);
            if (device == null) { return null; }
            return new AudioDevice { Id = GetId(device), Name = GetFriendlyName(device), IsDefault = true };
        }

        public static AudioStatus GetStatus()
        {
            AudioStatus status = new AudioStatus();
            IMMDeviceEnumerator enumerator = CreateEnumerator();

            IMMDevice output;
            if (enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out output) == 0
                && output != null)
            {
                status.HasOutput = true;
                status.OutputId = GetId(output);
                status.OutputName = GetFriendlyName(output);
            }

            IMMDevice input;
            if (enumerator.GetDefaultAudioEndpoint(EDataFlow.eCapture, ERole.eMultimedia, out input) == 0
                && input != null)
            {
                status.HasInput = true;
                status.InputId = GetId(input);
                status.InputName = GetFriendlyName(input);

                bool muted;
                if (GetEndpointVolume(input).GetMute(out muted) == 0) { status.InputMuted = muted; }
            }

            return status;
        }

        public static bool GetCaptureMute()
        {
            IMMDevice device = GetDefaultDevice(EDataFlow.eCapture, ERole.eMultimedia);
            if (device == null) { throw new InvalidOperationException("No active microphone was found."); }

            bool muted;
            Marshal.ThrowExceptionForHR(GetEndpointVolume(device).GetMute(out muted));
            return muted;
        }

        static void ApplyMute(IMMDevice device, bool mute)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(GetEndpointVolume(device).SetMute(mute, ref context));
        }

        /// <summary>
        /// Mutes the microphone. By default this covers both the multimedia
        /// default and the communications default, because conferencing apps
        /// use the latter and it is often a different device.
        /// </summary>
        public static int SetCaptureMute(bool mute, bool allDevices)
        {
            List<string> done = new List<string>();

            if (allDevices)
            {
                IMMDeviceEnumerator enumerator = CreateEnumerator();
                IMMDeviceCollection collection;
                Marshal.ThrowExceptionForHR(
                    enumerator.EnumAudioEndpoints(EDataFlow.eCapture, DEVICE_STATE_ACTIVE, out collection));

                int count;
                Marshal.ThrowExceptionForHR(collection.GetCount(out count));
                for (int i = 0; i < count; i++)
                {
                    IMMDevice device;
                    if (collection.Item(i, out device) != 0) { continue; }
                    ApplyMute(device, mute);
                    done.Add(GetId(device));
                }
            }
            else
            {
                ERole[] roles = new[] { ERole.eMultimedia, ERole.eCommunications };
                foreach (ERole role in roles)
                {
                    IMMDevice device = GetDefaultDevice(EDataFlow.eCapture, role);
                    if (device == null) { continue; }

                    string id = GetId(device);
                    if (done.Contains(id)) { continue; }

                    ApplyMute(device, mute);
                    done.Add(id);
                }
            }

            if (done.Count == 0) { throw new InvalidOperationException("No active microphone was found."); }
            return done.Count;
        }

        /// <summary>
        /// Read-only probe: reports which PolicyConfig interface this build of
        /// Windows answers to, without changing any device. Returns null when
        /// neither is available.
        /// </summary>
        public static string GetPolicyConfigFlavour()
        {
            object client;
            try { client = new PolicyConfigClientComObject(); }
            catch { return null; }

            string flavours = "";
            if (client as IPolicyConfig != null) { flavours += "IPolicyConfig "; }
            if (client as IPolicyConfigVista != null) { flavours += "IPolicyConfigVista "; }
            return flavours.Length == 0 ? null : flavours.Trim();
        }

        static readonly ERole[] AllRoles =
            new[] { ERole.eConsole, ERole.eMultimedia, ERole.eCommunications };

        public static void SetDefaultDevice(string deviceId)
        {
            string report;
            if (TrySetDefaultDevice(deviceId, out report)) { return; }
            throw new InvalidOperationException("Could not change the default audio device. " + report);
        }

        /// <summary>
        /// Applies a device as the default for every role, across whichever
        /// PolicyConfig interface this build of Windows answers to.
        ///
        /// Every role is attempted rather than stopping at the first failure:
        /// the roles are independent, and a machine that refuses one can still
        /// accept another. Succeeding on any of them counts, because a single
        /// applied role is the difference between the switch working and not.
        ///
        /// The report carries the exact HRESULTs. Without them a failure here
        /// is undiagnosable - PolicyConfig is undocumented, so the status code
        /// is the only evidence available.
        /// </summary>
        public static bool TrySetDefaultDevice(string deviceId, out string report)
        {
            StringBuilder log = new StringBuilder();
            object client;

            try
            {
                client = new PolicyConfigClientComObject();
            }
            catch (Exception error)
            {
                report = "PolicyConfig could not be created: " + error.Message;
                return false;
            }

            if (Apply(client as IPolicyConfig, deviceId, log) ||
                Apply(client as IPolicyConfigVista, deviceId, log))
            {
                report = log.ToString().Trim();
                return true;
            }

            report = log.ToString().Trim();
            if (report.Length == 0) { report = "No PolicyConfig interface is available on this build of Windows."; }
            return false;
        }

        static bool Apply(IPolicyConfig target, string deviceId, StringBuilder log)
        {
            if (target == null) { log.Append("IPolicyConfig unsupported. "); return false; }

            bool any = false;
            foreach (ERole role in AllRoles)
            {
                try
                {
                    int hr = target.SetDefaultEndpoint(deviceId, role);
                    if (hr == 0) { any = true; } else { log.AppendFormat("IPolicyConfig/{0}=0x{1:X8} ", role, hr); }
                }
                catch (Exception error)
                {
                    log.AppendFormat("IPolicyConfig/{0} threw {1} ", role, error.GetType().Name);
                }
            }
            return any;
        }

        static bool Apply(IPolicyConfigVista target, string deviceId, StringBuilder log)
        {
            if (target == null) { log.Append("IPolicyConfigVista unsupported. "); return false; }

            bool any = false;
            foreach (ERole role in AllRoles)
            {
                try
                {
                    int hr = target.SetDefaultEndpoint(deviceId, role);
                    if (hr == 0) { any = true; } else { log.AppendFormat("Vista/{0}=0x{1:X8} ", role, hr); }
                }
                catch (Exception error)
                {
                    log.AppendFormat("Vista/{0} threw {1} ", role, error.GetType().Name);
                }
            }
            return any;
        }
    }

    public class BluetoothAudioDevice
    {
        public string Name;
        public ulong Address;
        public string AddressText;
        public bool Connected;
        public bool IsAudio;
        public override string ToString() { return Name; }
    }

    /// <summary>
    /// Connects and disconnects already-paired Bluetooth devices through the
    /// Win32 Bluetooth API. Pairing itself is deliberately out of scope - that
    /// needs a trust prompt and belongs in the Windows Settings UI.
    /// </summary>
    public static class Bluetooth
    {
        const uint BLUETOOTH_SERVICE_DISABLE = 0;
        const uint BLUETOOTH_SERVICE_ENABLE = 1;
        const int ERROR_NOT_FOUND = 1168;

        // Enabling A2DP is what actually brings a headset online; the
        // hands-free service is what gives it a working microphone.
        static readonly Guid[] AudioServices = new[]
        {
            new Guid("0000110B-0000-1000-8000-00805F9B34FB"), // A2DP audio sink
            new Guid("0000111E-0000-1000-8000-00805F9B34FB")  // hands-free
        };

        [StructLayout(LayoutKind.Sequential)]
        struct SYSTEMTIME
        {
            public ushort wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct BLUETOOTH_DEVICE_INFO
        {
            public int dwSize;
            public ulong Address;
            public uint ulClassofDevice;
            [MarshalAs(UnmanagedType.Bool)] public bool fConnected;
            [MarshalAs(UnmanagedType.Bool)] public bool fRemembered;
            [MarshalAs(UnmanagedType.Bool)] public bool fAuthenticated;
            public SYSTEMTIME stLastSeen;
            public SYSTEMTIME stLastUsed;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string szName;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct BLUETOOTH_DEVICE_SEARCH_PARAMS
        {
            public int dwSize;
            [MarshalAs(UnmanagedType.Bool)] public bool fReturnAuthenticated;
            [MarshalAs(UnmanagedType.Bool)] public bool fReturnRemembered;
            [MarshalAs(UnmanagedType.Bool)] public bool fReturnUnknown;
            [MarshalAs(UnmanagedType.Bool)] public bool fReturnConnected;
            [MarshalAs(UnmanagedType.Bool)] public bool fIssueInquiry;
            public byte cTimeoutMultiplier;
            public IntPtr hRadio;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct BLUETOOTH_FIND_RADIO_PARAMS
        {
            public int dwSize;
        }

        [DllImport("bthprops.cpl", SetLastError = true)]
        static extern IntPtr BluetoothFindFirstRadio(ref BLUETOOTH_FIND_RADIO_PARAMS pbtfrp, out IntPtr phRadio);
        [DllImport("bthprops.cpl", SetLastError = true)]
        static extern bool BluetoothFindNextRadio(IntPtr hFind, out IntPtr phRadio);
        [DllImport("bthprops.cpl", SetLastError = true)]
        static extern bool BluetoothFindRadioClose(IntPtr hFind);
        [DllImport("bthprops.cpl", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr BluetoothFindFirstDevice(ref BLUETOOTH_DEVICE_SEARCH_PARAMS pbtsp,
                                                      ref BLUETOOTH_DEVICE_INFO pbtdi);
        [DllImport("bthprops.cpl", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool BluetoothFindNextDevice(IntPtr hFind, ref BLUETOOTH_DEVICE_INFO pbtdi);
        [DllImport("bthprops.cpl", SetLastError = true)]
        static extern bool BluetoothFindDeviceClose(IntPtr hFind);
        [DllImport("bthprops.cpl", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int BluetoothGetDeviceInfo(IntPtr hRadio, ref BLUETOOTH_DEVICE_INFO pbtdi);
        [DllImport("bthprops.cpl", SetLastError = true)]
        static extern int BluetoothSetServiceState(IntPtr hRadio, ref BLUETOOTH_DEVICE_INFO pbtdi,
                                                   ref Guid pGuidService, uint dwServiceFlags);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr hObject);

        static List<IntPtr> OpenRadios()
        {
            List<IntPtr> radios = new List<IntPtr>();
            BLUETOOTH_FIND_RADIO_PARAMS parameters = new BLUETOOTH_FIND_RADIO_PARAMS();
            parameters.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_FIND_RADIO_PARAMS));

            IntPtr radio;
            IntPtr find = BluetoothFindFirstRadio(ref parameters, out radio);
            if (find == IntPtr.Zero) { return radios; }

            try
            {
                do { radios.Add(radio); } while (BluetoothFindNextRadio(find, out radio));
            }
            finally { BluetoothFindRadioClose(find); }

            return radios;
        }

        static void CloseRadios(List<IntPtr> radios)
        {
            foreach (IntPtr radio in radios) { CloseHandle(radio); }
        }

        static string FormatAddress(ulong address)
        {
            byte[] bytes = BitConverter.GetBytes(address);
            return string.Format("{0:X2}:{1:X2}:{2:X2}:{3:X2}:{4:X2}:{5:X2}",
                                 bytes[5], bytes[4], bytes[3], bytes[2], bytes[1], bytes[0]);
        }

        /// <summary>Major device class 0x04 is Audio/Video.</summary>
        static bool IsAudioClass(uint classOfDevice)
        {
            return ((classOfDevice >> 8) & 0x1F) == 0x04;
        }

        public static bool HasRadio()
        {
            List<IntPtr> radios = OpenRadios();
            try { return radios.Count > 0; }
            finally { CloseRadios(radios); }
        }

        public static BluetoothAudioDevice[] ListPaired(bool audioOnly)
        {
            Dictionary<ulong, BluetoothAudioDevice> found = new Dictionary<ulong, BluetoothAudioDevice>();
            List<IntPtr> radios = OpenRadios();

            try
            {
                foreach (IntPtr radio in radios)
                {
                    BLUETOOTH_DEVICE_SEARCH_PARAMS search = new BLUETOOTH_DEVICE_SEARCH_PARAMS();
                    search.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_SEARCH_PARAMS));
                    search.fReturnAuthenticated = true;
                    search.fReturnRemembered = true;
                    search.fReturnConnected = true;
                    search.fReturnUnknown = false;
                    search.fIssueInquiry = false;   // no scan: paired devices only, so this stays fast
                    search.cTimeoutMultiplier = 0;
                    search.hRadio = radio;

                    BLUETOOTH_DEVICE_INFO info = new BLUETOOTH_DEVICE_INFO();
                    info.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_INFO));

                    IntPtr find = BluetoothFindFirstDevice(ref search, ref info);
                    if (find == IntPtr.Zero) { continue; }

                    try
                    {
                        while (true)
                        {
                            bool isAudio = IsAudioClass(info.ulClassofDevice);
                            if ((!audioOnly || isAudio) && !found.ContainsKey(info.Address))
                            {
                                found[info.Address] = new BluetoothAudioDevice
                                {
                                    Name = string.IsNullOrEmpty(info.szName)
                                           ? FormatAddress(info.Address) : info.szName,
                                    Address = info.Address,
                                    AddressText = FormatAddress(info.Address),
                                    Connected = info.fConnected,
                                    IsAudio = isAudio
                                };
                            }

                            info.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_INFO));
                            if (!BluetoothFindNextDevice(find, ref info)) { break; }
                        }
                    }
                    finally { BluetoothFindDeviceClose(find); }
                }
            }
            finally { CloseRadios(radios); }

            List<BluetoothAudioDevice> devices = new List<BluetoothAudioDevice>(found.Values);
            devices.Sort(delegate(BluetoothAudioDevice a, BluetoothAudioDevice b)
            {
                return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
            });
            return devices.ToArray();
        }

        /// <summary>Blocks until the radio answers. Returns a Win32 error code, 0 on success.</summary>
        public static int SetConnected(ulong address, bool connect)
        {
            uint flag = connect ? BLUETOOTH_SERVICE_ENABLE : BLUETOOTH_SERVICE_DISABLE;
            int lastError = ERROR_NOT_FOUND;
            List<IntPtr> radios = OpenRadios();

            try
            {
                foreach (IntPtr radio in radios)
                {
                    BLUETOOTH_DEVICE_INFO info = new BLUETOOTH_DEVICE_INFO();
                    info.dwSize = Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_INFO));
                    info.Address = address;

                    // Fails when this radio has never seen the device; try the next one.
                    if (BluetoothGetDeviceInfo(radio, ref info) != 0) { continue; }

                    bool any = false;
                    foreach (Guid service in AudioServices)
                    {
                        Guid target = service;
                        int result = BluetoothSetServiceState(radio, ref info, ref target, flag);
                        if (result == 0) { any = true; } else { lastError = result; }
                    }

                    if (any) { return 0; }
                }
            }
            finally { CloseRadios(radios); }

            return lastError;
        }

        // Connecting can take the better part of ten seconds, which would
        // freeze the tray. The work runs on a plain .NET thread and the result
        // is picked up by the UI timer, so no callback ever has to cross back
        // into PowerShell from a foreign thread.
        static int _busy;
        static readonly object _sync = new object();
        static string _pendingName = "";
        static bool _pendingConnect;
        static bool _hasResult;
        static int _result;

        public static bool IsBusy { get { return Volatile.Read(ref _busy) != 0; } }

        public static bool BeginSetConnected(ulong address, bool connect, string displayName)
        {
            if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) { return false; }

            lock (_sync)
            {
                _pendingName = displayName;
                _pendingConnect = connect;
                _hasResult = false;
                _result = 0;
            }

            Thread worker = new Thread(delegate()
            {
                int outcome;
                try { outcome = SetConnected(address, connect); }
                catch (Exception) { outcome = -1; }

                lock (_sync) { _result = outcome; _hasResult = true; }
                Volatile.Write(ref _busy, 0);
            });
            worker.IsBackground = true;
            worker.Start();
            return true;
        }

        /// <summary>Returns a message once, then null until the next request.</summary>
        public static string TakeResultMessage()
        {
            lock (_sync)
            {
                if (!_hasResult) { return null; }
                _hasResult = false;

                if (_result == 0)
                {
                    return (_pendingConnect ? "Connected to " : "Disconnected ") + _pendingName;
                }
                if (_result == ERROR_NOT_FOUND)
                {
                    return _pendingName + " did not respond. Is it powered on and in range?";
                }
                return (_pendingConnect ? "Could not connect to " : "Could not disconnect ")
                       + _pendingName + " (error " + _result + ")";
            }
        }
    }

    public static class Native
    {
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern uint GetConsoleProcessList(uint[] processList, uint count);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        const int SW_HIDE = 0;

        /// <summary>
        /// Hides the console window, but only when this process is the sole
        /// owner of it. Launched from a shortcut that is true and the window is
        /// just a flash of black; launched from an existing prompt it is the
        /// user's own window, and hiding that would be rude.
        /// </summary>
        public static bool HideOwnConsole()
        {
            IntPtr window = GetConsoleWindow();
            if (window == IntPtr.Zero) { return false; }

            uint[] owners = new uint[4];
            if (GetConsoleProcessList(owners, (uint)owners.Length) != 1) { return false; }

            return ShowWindow(window, SW_HIDE);
        }
    }

    /// <summary>
    /// A borderless status pop-up that never takes focus, so toggling the mic
    /// mid-sentence does not steal your keystrokes.
    /// </summary>
    public class OsdForm : System.Windows.Forms.Form
    {
        protected override bool ShowWithoutActivation { get { return true; } }

        protected override System.Windows.Forms.CreateParams CreateParams
        {
            get
            {
                System.Windows.Forms.CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW - keep it out of Alt+Tab
                return cp;
            }
        }
    }
}
'@

    try {
        Add-Type -TypeDefinition $source -ReferencedAssemblies $refs -ErrorAction Stop
    }
    catch {
        throw ("Could not build the audio interop layer on this machine. " +
               "Run Test-Compatibility.ps1 for a diagnosis, and see the " +
               "'If nothing scripted works' section of the README for the " +
               "shortcut-only fallback.`r`nUnderlying error: " + $_.Exception.Message)
    }

    $script:AudioTypesLoaded = $true
}

function Get-MicrophoneMute {
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::GetCaptureMute()
}

function Set-MicrophoneMute {
    param(
        [Parameter(Mandatory = $true)][bool]$Mute,
        [switch]$AllDevices
    )
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::SetCaptureMute($Mute, [bool]$AllDevices)
}

function Get-AudioDeviceList {
    # Emits one device per pipeline item; wrap calls in @() to get an array
    # back regardless of how many devices exist.
    param([switch]$Capture)
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::ListDevices([bool]$Capture)
}

function Get-DefaultAudioDevice {
    param([switch]$Capture)
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::GetDefault([bool]$Capture)
}

function Set-DefaultAudioDevice {
    param([Parameter(Mandatory = $true)][string]$Id)
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::SetDefaultDevice($Id)
}

function Test-DefaultDeviceSupport {
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::GetPolicyConfigFlavour()
}

function Get-AudioStatus {
    # One pass over the defaults. Cheap enough to call on a one-second timer.
    Initialize-AudioTypes
    [WinAudioToggle.Audio]::GetStatus()
}

function Get-OutputRotation {
    <#
        Resolves outputs.txt into an ordered list of live devices, so the tray
        and the one-shot switcher cycle in the same order.

        Returns an empty array when there is no usable preference file, which
        tells the caller to fall back to every active device by name.
    #>
    param(
        [Parameter(Mandatory = $true)]$Devices,
        [string]$ConfigDirectory
    )

    $candidates = @()
    if ($ConfigDirectory) { $candidates += (Join-Path $ConfigDirectory 'outputs.txt') }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $candidates += (Join-Path $repoRoot 'outputs.txt')
    $candidates += (Join-Path $repoRoot 'taskbar\outputs.txt')

    $path = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $path) { return @() }

    $ordered = @()
    foreach ($line in Get-Content -LiteralPath $path) {
        $pattern = $line.Trim()
        if (-not $pattern -or $pattern.StartsWith('#')) { continue }

        $match = $Devices | Where-Object { $_.Name -like "*$pattern*" } | Select-Object -First 1
        if ($match -and ($ordered -notcontains $match)) { $ordered += $match }
    }

    if ($ordered.Count -lt 2) { return @() }
    return $ordered
}

function Get-PairedBluetoothDevice {
    <#
        Paired Bluetooth devices, audio ones first. Falls back to every paired
        device when nothing reports the Audio/Video class, since a few headsets
        describe themselves oddly and an empty menu is no help to anyone.
    #>
    Initialize-AudioTypes

    $devices = @([WinAudioToggle.Bluetooth]::ListPaired($true))
    if ($devices.Count -eq 0) { $devices = @([WinAudioToggle.Bluetooth]::ListPaired($false)) }
    $devices
}

function Test-BluetoothRadio {
    Initialize-AudioTypes
    [WinAudioToggle.Bluetooth]::HasRadio()
}

function Start-BluetoothConnect {
    param(
        [Parameter(Mandatory = $true)][uint64]$Address,
        [Parameter(Mandatory = $true)][bool]$Connect,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )
    Initialize-AudioTypes
    [WinAudioToggle.Bluetooth]::BeginSetConnected($Address, $Connect, $DisplayName)
}

function Receive-BluetoothResult {
    Initialize-AudioTypes
    [WinAudioToggle.Bluetooth]::TakeResultMessage()
}

function Hide-OwnConsoleWindow {
    Initialize-AudioTypes
    [WinAudioToggle.Native]::HideOwnConsole()
}

function Show-AudioOsd {
    <#
        Brief on-screen confirmation. Deliberately not a balloon tip: on
        Windows 10/11 those become toasts and pile up in the notification
        centre, which gets old fast for something you click all day.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Detail = '',
        [ValidateSet('Normal', 'Alert')][string]$Style = 'Normal',
        [int]$DurationMs = 1300
    )

    Initialize-AudioTypes

    $form = New-Object WinAudioToggle.OsdForm
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Size = New-Object System.Drawing.Size(340, 88)
    $form.Opacity = 0.94
    $form.BackColor = if ($Style -eq 'Alert') {
        [System.Drawing.Color]::FromArgb(122, 32, 32)
    } else {
        [System.Drawing.Color]::FromArgb(28, 28, 30)
    }

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(
        ($screen.X + [int](($screen.Width - $form.Width) / 2)),
        ($screen.Y + $screen.Height - $form.Height - 24))

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.AutoSize = $false
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $titleLabel.SetBounds(10, 14, ($form.Width - 20), 28)
    $form.Controls.Add($titleLabel)

    if ($Detail) {
        $detailLabel = New-Object System.Windows.Forms.Label
        $detailLabel.Text = $Detail
        $detailLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 195)
        $detailLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $detailLabel.AutoSize = $false
        $detailLabel.AutoEllipsis = $true
        $detailLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $detailLabel.SetBounds(10, 44, ($form.Width - 20), 26)
        $form.Controls.Add($detailLabel)
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $DurationMs
    $timer.Add_Tick({ $timer.Stop(); $form.Close() }.GetNewClosure())
    $form.Add_Shown({ $timer.Start() }.GetNewClosure())

    # Click anywhere to dismiss early.
    $dismiss = { $form.Close() }.GetNewClosure()
    $form.Add_Click($dismiss)
    foreach ($control in $form.Controls) { $control.Add_Click($dismiss) }

    try { [System.Windows.Forms.Application]::Run($form) }
    finally { $timer.Dispose(); $form.Dispose() }
}

function Write-AudioError {
    <#
        Shortcuts launch with a hidden window, so a thrown exception would be
        invisible. Show failures on screen instead, and still write to the
        error stream for anyone running from a console.
    #>
    param([Parameter(Mandatory = $true)][string]$Message)

    # The pop-up goes first, and -ErrorAction Continue is deliberate: callers
    # set $ErrorActionPreference = 'Stop', under which a plain Write-Error
    # would throw out of the catch block that called us.
    try { Show-AudioOsd -Title 'Audio control failed' -Detail $Message -Style Alert -DurationMs 4000 }
    catch { }

    Write-Error $Message -ErrorAction Continue
}
