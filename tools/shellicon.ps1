
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class ShellIcon {
 [DllImport("shell32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SHGetFileInfo(string p, uint a, ref SHFILEINFO i, uint cb, uint f);
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public struct SHFILEINFO { public IntPtr hIcon; public int iIcon; public uint dwAttributes; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szDisplayName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=80)] public string szTypeName; }
}
"@
$i = New-Object ShellIcon+SHFILEINFO
[ShellIcon]::SHGetFileInfo('D:/休闲小岛幻境/发布/休闲小岛幻境.exe',0,[ref]$i,[System.Runtime.InteropServices.Marshal]::SizeOf($i),0x100) | Out-Null
$small=[System.Drawing.Icon]::FromHandle($i.hIcon)
$small.ToBitmap().Save('D:/休闲小岛幻境/开发产物/shots/shell_small.png',[System.Drawing.Imaging.ImageFormat]::Png)
$i2 = New-Object ShellIcon+SHFILEINFO
[ShellIcon]::SHGetFileInfo('D:/休闲小岛幻境/发布/休闲小岛幻境.exe',0,[ref]$i2,[System.Runtime.InteropServices.Marshal]::SizeOf($i2),0x0) | Out-Null
$large=[System.Drawing.Icon]::FromHandle($i2.hIcon)
$large.ToBitmap().Save('D:/休闲小岛幻境/开发产物/shots/shell_large.png',[System.Drawing.Imaging.ImageFormat]::Png)
'small '+$small.Width+'x'+$small.Height+' large '+$large.Width+'x'+$large.Height
