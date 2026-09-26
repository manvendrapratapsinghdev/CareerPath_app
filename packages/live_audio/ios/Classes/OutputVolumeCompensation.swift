import Foundation

enum OutputVolumeCompensation {
  static func updatedTarget(
    currentTarget: Float,
    previousSystemVolume: Float,
    newSystemVolume: Float
  ) -> Float {
    let userDelta = newSystemVolume - previousSystemVolume
    return min(1.0, max(0.0, currentTarget + userDelta))
  }

  static func playerGain(
    target: Float,
    currentSystemVolume: Float
  ) -> Float {
    guard currentSystemVolume > 0.0001 else { return 1.0 }
    return min(1.0, max(0.0, target / currentSystemVolume))
  }
}
