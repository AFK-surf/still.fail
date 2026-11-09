// AMD PCI IDs known to be CPU-integrated graphics. The vendor ID alone cannot distinguish them from discrete cards,
// and Linux may not expose KFD's topology to the station user. Unknown IDs are kept rather than hiding a real card.
// Families and IDs: https://github.com/openbsd/src/blob/master/sys/dev/pci/drm/amd/amdgpu/amdgpu_devlist.h
const integrated = new Set([
  "9870", "9874", "9875", "9876", "9877", "98e4", // Carrizo, Stoney
  "15d8", "15dd", "15e7", "1636", "1638", "164c", // Raven, Renoir
  "164d", "1681", "1435", "163f", "164e", "13c0", "1506", // Rembrandt, Van Gogh, Raphael, Granite Ridge, Mendocino
  "15bf", "15c8", "1900", "1901", "150e", "1586", "1114", "1902", // Phoenix and newer
]);

export function amdIntegrated(deviceId: string | null | undefined): boolean {
  return deviceId !== null && deviceId !== undefined && integrated.has(deviceId.toLowerCase().replace(/^0x/, ""));
}
