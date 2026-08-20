
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace AudioTray
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

        // ---- changing the default device --------------------------------
        //
        // Windows has never shipped a public API for this, so every audio
        // switcher drives one of the shell's internal PolicyConfig interfaces.
        // Which coclass and which interface answer varies by Windows build, so
        // rather than assume one combination, all the known ones are tried and
        // the exact status codes recorded.
        //
        // Activation context is part of the matrix on purpose. An out-of-process
        // activation returns a proxy, and QueryInterface across a proxy needs
        // the interface registered for marshalling - which these undocumented
        // ones are not. In-process activation is therefore tried first, and a
        // proxy is the leading explanation for a QueryInterface that fails
        // against a coclass which itself created successfully.

        static readonly Guid IID_IUnknown = new Guid("00000000-0000-0000-C000-000000000046");
        static readonly Guid IID_IPolicyConfig = new Guid("f8679f50-850a-45de-be8b-c4348c9a0d0b");
        static readonly Guid IID_IPolicyConfigVista = new Guid("568b9108-44bf-40b4-9006-86afe5b5a620");

        const int CLSCTX_INPROC_SERVER = 0x1;
        const int CLSCTX_SERVER = 0x15;

        [DllImport("ole32.dll")]
        static extern int CoCreateInstance(ref Guid rclsid, IntPtr outer, int context,
                                           ref Guid riid, out IntPtr instance);

        sealed class PolicySource
        {
            public string Name;
            public Guid ClassId;
            public int Context;
            public string ContextName;
        }

        static PolicySource[] PolicySources()
        {
            Guid client = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");       // CPolicyConfigClient
            Guid vistaClient = new Guid("294935ce-f637-4e7c-a41b-ab255460b862");  // CPolicyConfigVistaClient

            return new[]
            {
                new PolicySource { Name = "Client",      ClassId = client,      Context = CLSCTX_INPROC_SERVER, ContextName = "inproc" },
                new PolicySource { Name = "Client",      ClassId = client,      Context = CLSCTX_SERVER,        ContextName = "server" },
                new PolicySource { Name = "VistaClient", ClassId = vistaClient, Context = CLSCTX_INPROC_SERVER, ContextName = "inproc" },
                new PolicySource { Name = "VistaClient", ClassId = vistaClient, Context = CLSCTX_SERVER,        ContextName = "server" }
            };
        }

        static readonly ERole[] AllRoles =
            new[] { ERole.eConsole, ERole.eMultimedia, ERole.eCommunications };

        delegate int SetEndpoint(string deviceId, ERole role);

        public static void SetDefaultDevice(string deviceId)
        {
            string report;
            if (TrySetDefaultDevice(deviceId, out report)) { return; }
            throw new InvalidOperationException("Could not change the default audio device. " + report);
        }

        /// <summary>
        /// Walks every known coclass, activation context and interface until one
        /// applies the device, then applies it for all three roles.
        ///
        /// Every role is attempted rather than stopping at the first failure:
        /// the roles are independent, and a build that refuses one can still
        /// accept another. Any single success counts, since one applied role is
        /// the difference between the switch working and not.
        /// </summary>
        public static bool TrySetDefaultDevice(string deviceId, out string report)
        {
            StringBuilder log = new StringBuilder();

            foreach (PolicySource source in PolicySources())
            {
                IntPtr unknown = IntPtr.Zero;
                try
                {
                    Guid classId = source.ClassId;
                    Guid unknownId = IID_IUnknown;

                    int hr = CoCreateInstance(ref classId, IntPtr.Zero, source.Context, ref unknownId, out unknown);
                    if (hr != 0 || unknown == IntPtr.Zero)
                    {
                        log.AppendFormat("{0}/{1} create=0x{2:X8}; ", source.Name, source.ContextName, hr);
                        continue;
                    }

                    if (TryApply(unknown, source, deviceId, log))
                    {
                        report = log.ToString().Trim();
                        return true;
                    }
                }
                catch (Exception error)
                {
                    log.AppendFormat("{0}/{1} {2}; ", source.Name, source.ContextName, error.GetType().Name);
                }
                finally
                {
                    if (unknown != IntPtr.Zero) { Marshal.Release(unknown); }
                }
            }

            report = log.ToString().Trim();
            if (report.Length == 0) { report = "No PolicyConfig interface is available on this build of Windows."; }
            return false;
        }

        static bool TryApply(IntPtr unknown, PolicySource source, string deviceId, StringBuilder log)
        {
            IntPtr pointer;
            Guid iid = IID_IPolicyConfig;

            int hr = Marshal.QueryInterface(unknown, ref iid, out pointer);
            if (hr == 0)
            {
                try
                {
                    IPolicyConfig target =
                        (IPolicyConfig)Marshal.GetTypedObjectForIUnknown(pointer, typeof(IPolicyConfig));
                    if (ApplyRoles(deviceId, source, "IPolicyConfig", log,
                                   delegate(string id, ERole role) { return target.SetDefaultEndpoint(id, role); }))
                    {
                        return true;
                    }
                }
                finally { Marshal.Release(pointer); }
            }
            else
            {
                log.AppendFormat("{0}/{1} IPolicyConfig QI=0x{2:X8}; ", source.Name, source.ContextName, hr);
            }

            iid = IID_IPolicyConfigVista;
            hr = Marshal.QueryInterface(unknown, ref iid, out pointer);
            if (hr == 0)
            {
                try
                {
                    IPolicyConfigVista target =
                        (IPolicyConfigVista)Marshal.GetTypedObjectForIUnknown(pointer, typeof(IPolicyConfigVista));
                    if (ApplyRoles(deviceId, source, "Vista", log,
                                   delegate(string id, ERole role) { return target.SetDefaultEndpoint(id, role); }))
                    {
                        return true;
                    }
                }
                finally { Marshal.Release(pointer); }
            }
            else
            {
                log.AppendFormat("{0}/{1} Vista QI=0x{2:X8}; ", source.Name, source.ContextName, hr);
            }

            return false;
        }

        static bool ApplyRoles(string deviceId, PolicySource source, string interfaceName,
                               StringBuilder log, SetEndpoint set)
        {
            bool any = false;

            foreach (ERole role in AllRoles)
            {
                try
                {
                    int hr = set(deviceId, role);
                    if (hr == 0) { any = true; }
                    else { log.AppendFormat("{0}/{1}.{2}=0x{3:X8}; ", source.Name, interfaceName, role, hr); }
                }
                catch (Exception error)
                {
                    log.AppendFormat("{0}/{1}.{2} threw {3}; ", source.Name, interfaceName, role, error.GetType().Name);
                }
            }

            return any;
        }

        /// <summary>
        /// Read-only QueryInterface matrix, for diagnostics. Creates each
        /// coclass and asks it for each interface without changing anything.
        /// </summary>
        public static string GetPolicyConfigFlavour()
        {
            StringBuilder found = new StringBuilder();

            foreach (PolicySource source in PolicySources())
            {
                IntPtr unknown = IntPtr.Zero;
                try
                {
                    Guid classId = source.ClassId;
                    Guid unknownId = IID_IUnknown;

                    int hr = CoCreateInstance(ref classId, IntPtr.Zero, source.Context, ref unknownId, out unknown);
                    if (hr != 0 || unknown == IntPtr.Zero)
                    {
                        found.AppendFormat("{0}/{1}: create=0x{2:X8};", source.Name, source.ContextName, hr);
                        continue;
                    }

                    found.AppendFormat("{0}/{1}: created, {2} {3};",
                                       source.Name, source.ContextName,
                                       DescribeQuery(unknown, "IPolicyConfig", IID_IPolicyConfig),
                                       DescribeQuery(unknown, "Vista", IID_IPolicyConfigVista));
                }
                catch (Exception error)
                {
                    found.AppendFormat("{0}/{1}: {2};", source.Name, source.ContextName, error.GetType().Name);
                }
                finally
                {
                    if (unknown != IntPtr.Zero) { Marshal.Release(unknown); }
                }
            }

            return found.ToString();
        }

        static string DescribeQuery(IntPtr unknown, string label, Guid interfaceId)
        {
            IntPtr pointer;
            Guid iid = interfaceId;

            int hr = Marshal.QueryInterface(unknown, ref iid, out pointer);
            if (hr == 0) { Marshal.Release(pointer); return label + "=YES"; }
            return string.Format("{0}=0x{1:X8}", label, hr);
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
}
