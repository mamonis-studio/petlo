// ============================================================================
// petlo - Display Name Screen (build 18)
// ============================================================================
//
// 設定 → アカウント → 表示名 で開く編集画面。
// 一度家族共有で設定したあと、ここから自由に変更できる。
//
// 保存: PATCH /me (失敗してもローカルキャッシュは即時反映)。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/eyebrow_text.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/primary_button.dart';
import '../../providers/display_name_provider.dart';
import '../../widgets/forms/editorial_text_field.dart';

class DisplayNameScreen extends ConsumerStatefulWidget {
  const DisplayNameScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DisplayNameScreen(),
      ),
    );
  }

  @override
  ConsumerState<DisplayNameScreen> createState() => _DisplayNameScreenState();
}

class _DisplayNameScreenState extends ConsumerState<DisplayNameScreen> {
  late final TextEditingController _nameC;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(
      text: ref.read(displayNameProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  String? _validate(String v) {
    final String trimmed = v.trim();
    if (trimmed.isEmpty) return '表示名を入力してください';
    if (trimmed.length > 20) return '20文字以内で入力してください';
    return null;
  }

  Future<void> _onSave() async {
    final String trimmed = _nameC.text.trim();
    final String? err = _validate(trimmed);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _isSaving = true;
    });
    final bool ok =
        await ref.read(displayNameProvider.notifier).save(trimmed);
    if (!mounted) return;
    setState(() => _isSaving = false);
    final SnackBar snack = SnackBar(
      content: Text(ok ? '表示名を保存しました' : 'ローカルに保存しました(後で同期されます)'),
      behavior: SnackBarBehavior.floating,
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppTypography typo = AppTypography.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'DISPLAY NAME',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 10 * 0.2,
            color: colors.fg,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.fg),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.paddingPage,
            8,
            AppDimensions.paddingPage,
            AppDimensions.paddingPage * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel(
                'Display name',
                size: EyebrowSize.large,
                padding: EdgeInsets.fromLTRB(0, 0, 0, 16),
              ),
              Text(
                '家族共有グループのメンバーに表示される名前です。\n'
                '本名でなく愛称・続柄 (お父さん、ママ、など) でも OK。',
                style: typo.bodyMedium
                    .copyWith(color: colors.fgMuted, height: 1.7),
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              EditorialTextField(
                label: 'Your display name',
                controller: _nameC,
                hint: '例: お父さん, ママ',
                required: true,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                errorText: _error,
                autofocus: true,
              ),
              const SizedBox(height: AppDimensions.paddingSection),

              PrimaryButton(
                label: _isSaving ? 'Saving...' : 'Save',
                onPressed: _isSaving ? null : _onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
