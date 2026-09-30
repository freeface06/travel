/// @intent 드롭다운 팝업 메뉴 전용 초슬림 인셋 디바이더 컴포넌트
/// @agent Gemini/manager-develop
/// @branch feat/flutter-migration
/// @author @developer_name
/// @date 2026-09-30
library;

import 'package:flutter/material.dart';

/// 팝업 메뉴 내에서 은은하고 세련된 여백과 라인을 제공하는 인셋 구분선
class AppMenuDivider extends PopupMenuEntry<Never> {
  @override
  final double height;
  final Color color;
  final double indent;
  final double endIndent;

  const AppMenuDivider({
    super.key,
    this.height = 1.0,
    this.color = const Color(0xFFF1F5F9),
    this.indent = 12.0,
    this.endIndent = 12.0,
  });

  @override
  bool represents(void value) => false;

  @override
  State<AppMenuDivider> createState() => _AppMenuDividerState();
}

class _AppMenuDividerState extends State<AppMenuDivider> {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: widget.height,
      thickness: 0.75,
      color: widget.color,
      indent: widget.indent,
      endIndent: widget.endIndent,
    );
  }
}
