import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // JSON 응답 처리

import 'package:http_parser/http_parser.dart';

class DiaryScreen extends StatefulWidget {
  @override
  _DiaryScreenState createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final TextEditingController _diaryController = TextEditingController();
  String _emotionResult = '😊 안정적인 상태입니다.';
  bool _isRecording = false;

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }


  void _analyzeEmotion() {
    String text = _diaryController.text;
    // 간단한 감정 분석 시뮬레이션
    if (text.contains("우울") || text.contains("힘들어")) {
      _emotionResult = '😢 우울한 감정이 감지되었습니다.';
    } else if (text.contains("행복") || text.contains("좋아")) {
      _emotionResult = '😊 긍정적인 감정이 감지되었습니다.';
    } else {
      _emotionResult = '😐 중립적인 상태입니다.';
    }

    setState(() {});
  }

  void _saveDiary() {
    final text = _diaryController.text.trim();
    if (text.isEmpty) return;

    _analyzeEmotion();

    // TODO: Firebase 저장 로직 추가
    print("일기 저장됨: $text");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("일기가 저장되었습니다")),
    );
  }

  void _viewPastEntries() {
    // TODO: 이전 일기 보기 화면으로 이동
    print("이전 일기 보기로 이동");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("감정 일기"),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _viewPastEntries,
            tooltip: '이전 일기 보기',
          )
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [

            // 텍스트 입력창
            TextField(
              controller: _diaryController,
              maxLines: 7,
              decoration: InputDecoration(
                labelText: "오늘 하루 어땠나요?",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // 음성 녹음 버튼
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
                  label: Text(_isRecording ? "녹음 중지" : "음성 녹음"),
                ),
                SizedBox(width: 16),
                Text(
                  _isRecording ? "녹음 중..." : "",
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
            SizedBox(height: 16),

            // 감정 분석 결과
            Row(
              children: [
                Icon(Icons.insights, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  _emotionResult,
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
            SizedBox(height: 16),

            // 저장 버튼
            ElevatedButton.icon(
              onPressed: _saveDiary,
              icon: Icon(Icons.save),
              label: Text("일기 저장하기"),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String? _audioPath;

  Future<void> _startRecording() async {
    await Permission.microphone.request();
    if (await Permission.microphone.isGranted) {
      final dir = await getTemporaryDirectory();
      _audioPath = '${dir.path}/temp.m4a';

      await _recorder.openRecorder();
      await _recorder.startRecorder(
        toFile: _audioPath,
        codec: Codec.aacMP4,
      );

      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _stopRecordingAndSend() async {
    await _recorder.stopRecorder();
    await _recorder.closeRecorder();

    setState(() {
      _isRecording = false;
    });

    if (_audioPath != null) {
      await _uploadAudio(File(_audioPath!));
    }
  }

  Future<void> _uploadAudio(File audioFile) async {
    final uri = Uri.parse('http://10.0.2.2:8000/transcribe'); // 서버가 /transcribe/면 그대로 맞추기
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        audioFile.path,
        contentType: MediaType('audio', 'mp4'),
      ));

    try {
      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      // 🔎 디버그용 로그
      debugPrint('HTTP ${response.statusCode}');
      debugPrint('BODY(len=${respStr.length}): ${respStr.substring(0, respStr.length.clamp(0, 200))}');

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서버 오류: ${response.statusCode}')),
        );
        return;
      }

      // 🛡️ JSON 파싱 가드
      Map<String, dynamic> data;
      try {
        data = jsonDecode(respStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('❌ JSON 파싱 실패: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버 응답 형식이 올바르지 않습니다.')),
        );
        return;
      }

      final newText = (data['text'] ?? '').toString();
      if (newText.trim().isEmpty) {
        debugPrint('⚠️ text가 비어있음');
      }

      final before = _diaryController.text;
      final combined = before.isEmpty ? newText : '$before\n$newText';

      // ✅ 프레임 이후에 텍스트/커서 반영 (간헐적 반영 이슈 예방)
      if (!mounted) return;
      setState(() {
        _diaryController.text = combined;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _diaryController.selection = TextSelection.fromPosition(
          TextPosition(offset: _diaryController.text.length),
        );
      });

    } catch (e) {
      debugPrint('❌ 업로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네트워크/업로드 오류가 발생했습니다.')),
      );
    }
  }

}
