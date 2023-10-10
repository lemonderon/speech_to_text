import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Web implementation of the SpeechToText platform interface. This supports
/// the speech to text functionality running in web browsers that have
/// SpeechRecognition support.
class SpeechToTextPlugin extends SpeechToTextPlatform {
  html.SpeechRecognition? _webSpeech;
  static const _doneNoResult = 'doneNoResult';
  bool _resultSent = false;
  bool _doneSent = false;

  /// Registers this class as the default instance of [SpeechToTextPlatform].
  static void registerWith(Registrar registrar) {
    print('registerWith');
    SpeechToTextPlatform.instance = SpeechToTextPlugin();
  }

  /// Returns true if the user has already granted permission to access the
  /// microphone, does not prompt the user.
  ///
  /// This method can be called before [initialize] to check if permission
  /// has already been granted. If this returns false then the [initialize]
  /// call will prompt the user for permission if it is allowed to do so.
  /// Note that applications cannot ask for permission again if the user has
  /// denied them permission in the past.
  @override
  Future<bool> hasPermission() async {
    print('hasPermission: ${html.SpeechRecognition.supported}');
    return html.SpeechRecognition.supported;
  }

  /// Initialize speech recognition services, returns true if
  /// successful, false if failed.
  ///
  /// This method must be called before any other speech functions.
  /// If this method returns false no further [SpeechToText] methods
  /// should be used. False usually means that the user has denied
  /// permission to use speech.
  ///
  /// [debugLogging] controls whether there is detailed logging from the underlying
  /// plugins. It is off by default, usually only useful for troubleshooting issues
  /// with a particular OS version or device, fairly verbose
  @override
  Future<bool> initialize(
      {debugLogging = false, List<SpeechConfigOption>? options}) async {
    print('initialize');
    if (!html.SpeechRecognition.supported) {
      print('!html.SpeechRecognition.supported');
      var error = SpeechRecognitionError('not supported', true);
      onError?.call(jsonEncode(error.toJson()));
      return false;
    }
    var initialized = false;
    try {
      print('_webSpeech = html.SpeechRecognition()');
      _webSpeech = html.SpeechRecognition();
      if (null != _webSpeech) {
        print('null != _webSpeech');
        _webSpeech!.onError.listen((error) => _onError(error));
        _webSpeech!.onStart.listen((startEvent) => _onSpeechStart(startEvent));
        _webSpeech!.onSpeechStart
            .listen((startEvent) => _onSpeechStart(startEvent));
        _webSpeech!.onEnd.listen((endEvent) => _onSpeechEnd(endEvent));
        // _webSpeech!.onSpeechEnd.listen((endEvent) => _onSpeechEnd(endEvent));
        _webSpeech!.onNoMatch
            .listen((noMatchEvent) => _onNoMatch(noMatchEvent));
        initialized = true;
      }
    } finally {
      if (null == _webSpeech) {
        print('finally: null != _webSpeech');
        if (null != onError) {
          print('finally: null != onError');
          var error = SpeechRecognitionError('speech_not_supported', true);
          print('finally: ${error.toJson()}');
          onError!(jsonEncode(error.toJson()));
        }
      }
    }
    print('initialize: $initialized');

    return initialized;
  }

  /// Stops the current listen for speech if active, does nothing if not.
  ///
  /// Stopping a listen session will cause a final result to be sent. Each
  /// listen session should be ended with either [stop] or [cancel], for
  /// example in the dispose method of a Widget. [cancel] is automatically
  /// invoked by a permanent error if [cancelOnError] is set to true in the
  /// [listen] call.
  ///
  /// *Note:* Cannot be used until a successful [initialize] call. Should
  /// only be used after a successful [listen] call.
  @override
  Future<void> stop() async {
    print('stop');
    if (null == _webSpeech) {
      print('stop: null == _webSpeech');
      return;
    }
    _webSpeech!.stop();
    print('stop: _webSpeech!.stop()');
  }

  /// Cancels the current listen for speech if active, does nothing if not.
  ///
  /// Canceling means that there will be no final result returned from the
  /// recognizer. Each listen session should be ended with either [stop] or
  /// [cancel], for example in the dispose method of a Widget. [cancel] is
  /// automatically invoked by a permanent error if [cancelOnError] is set
  /// to true in the [listen] call.
  ///
  /// *Note* Cannot be used until a successful [initialize] call. Should only
  /// be used after a successful [listen] call.
  @override
  Future<void> cancel() async {
    print('cancel');
    if (null == _webSpeech) {
      print('cancel: null == _webSpeech');
      return;
    }
    _webSpeech!.abort();
    print('cancel: _webSpeech!.abort()');
  }

  /// Starts a listening session for speech and converts it to text.
  ///
  /// Cannot be used until a successful [initialize] call. There is a
  /// time limit on listening imposed by both Android and iOS. The time
  /// depends on the device, network, etc. Android is usually quite short,
  /// especially if there is no active speech event detected, on the order
  /// of ten seconds or so.
  ///
  /// [localeId] is an optional locale that can be used to listen in a language
  /// other than the current system default. See [locales] to find the list of
  /// supported languages for listening.
  ///
  /// [partialResults] if true the listen reports results as they are recognized,
  /// when false only final results are reported. Defaults to true.
  ///
  /// [onDevice] if true the listen attempts to recognize locally with speech never
  /// leaving the device. If it cannot do this the listen attempt will fail. This is
  /// usually only needed for sensitive content where privacy or security is a concern.
  ///
  /// [sampleRate] optional for compatibility with certain iOS devices, some devices
  /// crash with `sampleRate != device's supported sampleRate`, try 44100 if seeing
  /// crashes
  ///
  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
  }) async {
    print('listen');
    if (null == _webSpeech) {
      print('listen: null == _webSpeech');
      return false;
    }
    _webSpeech!.onResult.listen((speechEvent) {
      print('listen: _onResult with speechEvent: $speechEvent');
      _onResult(speechEvent);
    });
    _webSpeech!.interimResults = partialResults;
    _webSpeech!.continuous = partialResults;
    if (null != localeId) {
      _webSpeech!.lang = localeId;
    }
    _doneSent = false;
    _resultSent = false;
    _webSpeech!.start();
    print('listen: _webSpeech!.start()');
    return true;
  }

  /// returns the list of speech locales available on the device.
  ///
  @override
  Future<List<dynamic>> locales() async {
    print('locales');
    var availableLocales = [];
    var lang = _webSpeech?.lang;
    if (null != lang && lang.isNotEmpty) {
      lang = lang.replaceAll(':', '_');
      availableLocales.add('$lang:$lang');
    }
    print('locales: availableLocales [$availableLocales]');
    return availableLocales;
  }

  void _onError(html.SpeechRecognitionError event) {
    print('onError');
    if (null != event.error) {
      print('onError: null != event.error');
      var error = SpeechRecognitionError(event.error!, false);
      print('onError: error.toJson()');
      onError?.call(jsonEncode(error.toJson()));
      _sendDone(_doneNoResult);
      print('onError: _sendDone');
    }
  }

  void _onSpeechStart(html.Event event) {
    print('onSpeechStart');
    onStatus?.call('listening');
    print('onSpeechStart: listening');
  }

  void _onSpeechEnd(html.Event event) {
    print('onSpeechEnd');
    onStatus?.call('notListening');
    print('onSpeechStart: notListening');
    _sendDone(_resultSent ? 'done' : _doneNoResult);
    print('onSpeechStart: _sendDone( ${_resultSent ? 'done' : _doneNoResult})');
  }

  void _onNoMatch(html.Event event) {
    print('onNoMatch');
    _sendDone(_doneNoResult);
    print('onNoMatch: _sendDone $_doneNoResult');
  }

  void _sendDone(String status) {
    print('sendDone');
    if (_doneSent) {
      print('sendDone: _doneSent');
      return;
    }
    onStatus?.call(status);
    print('sendDone: onStatus?.call(status)');
    _doneSent = true;
  }

  void _onResult(html.SpeechRecognitionEvent event) {
    print('onResult');
    var isFinal = false;
    var recogResults = <SpeechRecognitionWords>[];
    var results = event.results;
    if (null == results) {
      print('onResult: null == results');
      return;
    }
    for (var recognitionResult in results) {
      if (null == recognitionResult.length || recognitionResult.length == 0) {
        continue;
      }
      for (var altIndex = 0; altIndex < recognitionResult.length!; ++altIndex) {
        var alt = js_util.callMethod(recognitionResult, 'item', [altIndex]);
        if (null == alt) continue;
        String? transcript = js_util.getProperty(alt, 'transcript');
        num? confidence = js_util.getProperty(alt, 'confidence');
        print('onResult: transcript:$transcript and confidence:$confidence');
        if (null != transcript && null != confidence) {
          recogResults.add(
            SpeechRecognitionWords(
              transcript,
              confidence.toDouble(),
            ),
          );
        }
      }
    }
    var result = SpeechRecognitionResult(recogResults, isFinal);
    print('onResult: result: ${result.toJson()}');
    onTextRecognition?.call(jsonEncode(result.toJson()));
    _resultSent = true;
  }
}
