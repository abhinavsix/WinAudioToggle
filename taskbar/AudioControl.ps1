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

            if (client as IPolicyConfig != null) { return "IPolicyConfig"; }
            if (client as IPolicyConfigVista != null) { return "IPolicyConfigVista"; }
            return null;
        }

        public static void SetDefaultDevice(string deviceId)
        {
            object client = new PolicyConfigClientComObject();
            ERole[] roles = new[] { ERole.eConsole, ERole.eMultimedia, ERole.eCommunications };

            IPolicyConfig modern = client as IPolicyConfig;
            if (modern != null)
            {
                int hr = modern.SetDefaultEndpoint(deviceId, roles[0]);
                if (hr == 0)
                {
                    for (int i = 1; i < roles.Length; i++) { modern.SetDefaultEndpoint(deviceId, roles[i]); }
                    return;
                }
            }

            IPolicyConfigVista legacy = client as IPolicyConfigVista;
            if (legacy != null)
            {
                int hr = legacy.SetDefaultEndpoint(deviceId, roles[0]);
                if (hr == 0)
                {
                    for (int i = 1; i < roles.Length; i++) { legacy.SetDefaultEndpoint(deviceId, roles[i]); }
                    return;
                }
                Marshal.ThrowExceptionForHR(hr);
            }

            throw new InvalidOperationException(
                "Windows refused to change the default audio device on this machine.");
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
