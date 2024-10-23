import 'dart:typed_data';

/// A single frame of audio data.
///
/// Added to allow memoization of the VAD inference and subsequent clipping out
/// audio frames that are not speech. e.g. getting silence clipped out amounts
/// to frames.where(!isSilent).map(bytes).toList().
class AudioFrame {
  final Uint8List bytes;

  /// Probability that the frame contains speech.
  ///
  /// The VAD outputs a float from 0 to 1, representing the probability that
  /// the frame contains speech. >= this value is considered speech when
  /// deciding which frames to keep and when to stop recording, and also
  /// the value of the [AudioFrame.isSilent].
  double? vadP;
  AudioFrame({required this.bytes, this.vadP});
}