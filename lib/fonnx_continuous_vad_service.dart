import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fonnx/models/sileroVad/silero_vad.dart';
import 'package:fonnx_continuous_vad/vad_constants.dart';

import 'audio_frame.dart';
import 'circular_buffer.dart';

class FonnxContinuousVadService {
  final Duration maxDuration;
  final Duration maxSilenceDuration;
  final String vadModelPath;
  double voiceThreshold;
  var lastVadState = <String, dynamic>{};
  var lastVadStateIndex = 0;
  bool stopped = false;
  Timer? stopForMaxDurationTimer;
  final List<AudioFrame> _frames = [];

  /// Callback triggered when speech is first detected
  final Function(DateTime timestamp)? onSpeechDetected;
  final Function(List<AudioFrame> speech, DateTime timestamp)? onSpeechSegmentFinalized;

  bool speechDetectedInCurrentSegment = false;

  final CircularBuffer<Uint8List> _vadBufferQueue;

  // Track the start of the current speech segment
  bool isSpeechSegmentActive = false;

  // Silero VAD instance
  late final SileroVad _vad;

  FonnxContinuousVadService({
    required this.vadModelPath,
    this.maxDuration = const Duration(seconds: 10),
    this.maxSilenceDuration = const Duration(milliseconds: 1000),
    this.voiceThreshold = VadConstants.kVadPIsVoiceThreshold,
    this.onSpeechDetected,
    this.onSpeechSegmentFinalized,
  }) : _vadBufferQueue = CircularBuffer<Uint8List>(1000) {
    _vad = SileroVad.load(vadModelPath);
  }

  void start() {
    // Initialize the maxDuration timer
    _startMaxDurationTimer();

    // Start the VAD processing loop
    _vadInferenceLoop();
  }

  void stop() {
    stopForMaxDurationTimer?.cancel();
    stopped = true;
    _resetInternalState();
  }

  void addAudioData(Uint8List data) {
    if (!stopped) {
      _vadBufferQueue.add(data);
    }
  }

  void updateVoiceThreshold(double newThreshold) {
    voiceThreshold = newThreshold;
  }

  void _startMaxDurationTimer() {
    stopForMaxDurationTimer?.cancel(); // Cancel any existing timer
    stopForMaxDurationTimer = Timer(maxDuration, () {
      debugPrint('[FonnxContinuousVadService] Max duration timer triggered at ${DateTime.now()}');
      if (!speechDetectedInCurrentSegment) {
        debugPrint('[FonnxContinuousVadService] No speech detected. Resetting state and continuing.');
        _resetInternalState();
        _startMaxDurationTimer(); // Restart the timer
      } else {
        debugPrint('[FonnxContinuousVadService] Speech detected. Continuing processing.');
        _startMaxDurationTimer(); // Restart the timer
      }
    });
  }

  void _resetInternalState() {
    debugPrint('[FonnxContinuousVadService] Resetting internal state.');
    // Clear buffers and frames
    _vadBufferQueue.clear();
    _frames.clear();
    lastVadState = <String, dynamic>{};
    lastVadStateIndex = 0;
    speechDetectedInCurrentSegment = false;
    isSpeechSegmentActive = false;
    // Add any additional state resets if necessary
  }

  void _vadInferenceLoop() async {
    if (stopped) {
      return;
    }
    final hasBuffer = _vadBufferQueue.length > 0;
    if (hasBuffer) {
      final buffer = _vadBufferQueue.toList().first;
      _vadBufferQueue.removeFirst(); // Get and remove the first element
      await _processBufferAndVad(buffer);
      _vadInferenceLoop();
    } else {
      Future.delayed(
        const Duration(milliseconds: VadConstants.kMaxVadFrameMs),
        _vadInferenceLoop,
      );
    }
  }

  Future<void> _processBufferAndVad(Uint8List buffer) async {
    final frameSizeInBytes = (VadConstants.kSampleRate * VadConstants.kMaxVadFrameMs *
        VadConstants.kChannels *
        (VadConstants.kBitsPerSample / 8))
        .toInt() ~/
        1000;
    int index = 0;

    while ((index + 1) * frameSizeInBytes <= buffer.length) {
      final startIdx = index * frameSizeInBytes;
      final endIdx = (index + 1) * frameSizeInBytes;
      final frameBytes = buffer.sublist(startIdx, endIdx);
      final frame = AudioFrame(bytes: frameBytes);
      _frames.add(frame);
      final idx = _frames.length - 1;
      final nextVadState =
      await _vad.doInference(frameBytes, previousState: lastVadState);
      lastVadState = nextVadState;
      lastVadStateIndex = idx;
      final p = (nextVadState['output'] as Float32List).first;
      _frames[idx].vadP = p;

      // Trigger callback as soon as speech is detected, but only once per segment
      if (p >= voiceThreshold && !speechDetectedInCurrentSegment) {
        speechDetectedInCurrentSegment = true;
        isSpeechSegmentActive = true; // Mark the segment as active
        if (onSpeechDetected != null) {
          onSpeechDetected!(DateTime.now());
        }
      }

      if (_shouldFinalizeSegment(_frames)) {
        if (kDebugMode) {
          print('[FonnxContinuousVadService] Finalizing speech segment due to sustained silence.');
        }

        // Find the index of the first frame that was above the threshold
        int startFrameIndex = 0;
        for (int i = 0; i < _frames.length; i++) {
          if (_frames[i].vadP != null && _frames[i].vadP! >= voiceThreshold) {
            startFrameIndex = i;
            break;
          }
        }

        // Adjust the startFrameIndex to include 30% of the previous frames before the first speech frame
        final int startFrameIndexAdjusted = (startFrameIndex - (0.3 * startFrameIndex)).toInt();

        // Find the index of the last frame that was above the threshold
        int finalFrameIndex = _frames.length;
        for (int i = _frames.length - 1; i >= 0; i--) {
          if (_frames[i].vadP != null && _frames[i].vadP! >= voiceThreshold) {
            finalFrameIndex = i + 1;
            break;
          }
        }

        // Include all frames up to finalFrameIndex
        final finalizedFrames = _frames.sublist(startFrameIndexAdjusted, finalFrameIndex);

        // Instead of adding to the stream, we trigger the callback
        onSpeechSegmentFinalized!(finalizedFrames, DateTime.now());

        // Remove the finalized frames from the buffer
        _frames.removeRange(0, finalFrameIndex);

        // Reset the speech detection flag after segment finalization
        speechDetectedInCurrentSegment = false;
        isSpeechSegmentActive = false;
        lastVadState = <String, dynamic>{};
        lastVadStateIndex = 0;

        // Restart the maxDuration timer
        _startMaxDurationTimer();
      }
      index++;
    }
  }

  bool _shouldFinalizeSegment(List<AudioFrame> frames) {
    if (frames.isEmpty) {
      return false;
    }

    // Check if there is an active speech segment
    if (!isSpeechSegmentActive) {
      return false;
    }

    // Count the number of consecutive silent frames at the end
    int silentFrames = 0;
    for (int i = frames.length - 1; i >= 0; i--) {
      final p = frames[i].vadP;
      if (p != null && p < voiceThreshold) {
        silentFrames++;
      } else {
        break; // Stop counting when a non-silent frame is found
      }
    }

    final silentDuration = silentFrames * VadConstants.kMaxVadFrameMs;
    return silentDuration >= maxSilenceDuration.inMilliseconds;
  }
}
