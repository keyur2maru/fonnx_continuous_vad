import 'package:record/record.dart' show AudioEncoder;

class VadConstants {
  /// Format of audio bytes from microphone.
  static const kEncoder = AudioEncoder.pcm16bits;

  /// Sample rate in Hz
  static const int kSampleRate = 16000;

  /// Number of audio channels
  static const int kChannels = 1;

  /// Bits per sample, assuming 16-bit PCM audio
  static const int kBitsPerSample = 16;

  /// Maximum VAD frame duration in milliseconds
  static const int kMaxVadFrameMs = 30;

  /// Recommended VAD probability threshold for speech.
  static const double kVadPIsVoiceThreshold = 0.1;
}
