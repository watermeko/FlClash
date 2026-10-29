import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _exportFileName = 'rules.yaml';

class AddedRulesView extends ConsumerStatefulWidget {
  const AddedRulesView({super.key});

  @override
  ConsumerState<AddedRulesView> createState() => _AddedRulesViewState();
}

class _AddedRulesViewState extends ConsumerState<AddedRulesView> {
  final _key = uniqueId;
  var _query = SearchQuery('');
  final _searchTexts = Expando<String>();

  List<Rule> _visibleRules(List<Rule> rules) {
    return rules
        .whereMatches(_query, (rule) => rule.searchFields, texts: _searchTexts)
        .toList();
  }

  void _handleSearch(String query) {
    setState(() {
      _query = SearchQuery(query);
    });
  }

  Future<void> _handleAddOrUpdate([Rule? rule]) async {
    final res = await showFormSheet<Rule>(
      context: context,
      builder: (_) => RuleForm(rule: rule),
    );
    if (res == null || !mounted) {
      return;
    }
    ref.read(globalRulesProvider.notifier).put(res);
  }

  void _handleQuickActions() {
    showSheet<void>(
      context: context,
      builder: (_) => RulePresetSheet(
        onAdd: (rules) => ref.read(globalRulesProvider.notifier).putAll(rules),
      ),
    );
  }

  Future<void> _handleImport() async {
    final appLocalizations = context.appLocalizations;
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null || !mounted) {
      return;
    }
    final content = await globalState.safeRun(
      () async => utf8.decode(await file.readBytes()),
    );
    if (content == null || !mounted) {
      return;
    }
    final ({List<Rule> rules, int skipped}) imported;
    try {
      imported = readAddedRulesImport(
        content,
        existing: ref.read(globalRulesProvider).value ?? const [],
      );
    } on RuleImportException catch (error) {
      await _showImportIssue(error);
      return;
    }
    if (imported.rules.isEmpty && imported.skipped == 0) {
      await dialogs.showAlert(
        title: appLocalizations.importFile,
        message: TextSpan(text: appLocalizations.ruleListInvalid),
      );
      return;
    }
    ref.read(globalRulesProvider.notifier).putAll(imported.rules);
    if (!mounted) {
      return;
    }
    context.showNotifier(
      appLocalizations.rulesImportResult(
        imported.rules.length,
        imported.skipped,
      ),
      level: MessageLevel.success,
    );
  }

  Future<void> _showImportIssue(RuleImportException error) {
    final appLocalizations = context.appLocalizations;
    final message = switch (error.issue) {
      RuleImportIssue.text => appLocalizations.ruleTextInvalid,
      RuleImportIssue.payload => error.payloadError!.getMessage(context),
      RuleImportIssue.content => appLocalizations.contentNotEmpty,
      RuleImportIssue.target => appLocalizations.splitStrategyNotEmpty,
    };
    return dialogs.showAlert(
      title: appLocalizations.importFile,
      message: TextSpan(
        text: appLocalizations.lineIssueTip(error.line, message),
      ),
    );
  }

  Future<void> _handleExport() async {
    final appLocalizations = context.appLocalizations;
    final rules = ref.read(globalRulesProvider).value ?? const <Rule>[];
    final res = await globalState.safeRun<bool>(() async {
      final uri = await picker.saveFile(
        _exportFileName,
        utf8.encode('rules:\n${encodeRuleList(rules)}'),
      );
      return uri != null;
    }, title: appLocalizations.exportFile);
    if (res == true && mounted) {
      context.showNotifier(
        appLocalizations.exportSuccess,
        level: MessageLevel.success,
      );
    }
  }

  void _handleSelected(int ruleId) {
    ref.read(itemsProvider(_key).notifier).update((selectedRules) {
      final newSelectedRules = Set<int>.from(selectedRules)
        ..addOrRemove(ruleId);
      return newSelectedRules;
    });
  }

  void _handleSelectAll() {
    final ids = _visibleRules(
      ref.read(globalRulesProvider).value ?? [],
    ).map((item) => item.id).toSet();
    ref.read(itemsProvider(_key).notifier).update((selected) {
      return selected.containsAll(ids) ? {} : ids;
    });
  }

  Future<void> _handleDelete() async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteMultipTip(appLocalizations.rule),
      ),
      destructive: true,
      confirmText: appLocalizations.delete,
    );
    if (res != true || !mounted) {
      return;
    }
    final selectedRules = ref.read(itemsProvider(_key));
    final deletedIds = _visibleRules(
      ref.read(globalRulesProvider).value ?? [],
    ).map((item) => item.id).where(selectedRules.contains).toSet();
    ref.read(globalRulesProvider.notifier).delAll(deletedIds);
    ref.read(itemsProvider(_key).notifier).value = selectedRules.difference(
      deletedIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final rulesState = ref.watch(globalRulesProvider);
    final rules = _visibleRules(rulesState.value ?? []);
    final isSearching = _query.isNotEmpty;
    final selectedRules = ref.watch(itemsProvider(_key));
    final isSelecting = selectedRules.isNotEmpty;
    final selectionActions = [
      IconButtonData(
        glyph: AppGlyphs.delete,
        onPressed: _handleDelete,
        tooltip: appLocalizations.delete,
      ),
      IconButtonData(
        glyph: AppGlyphs.selectAll,
        onPressed: _handleSelectAll,
        tooltip: appLocalizations.selectAll,
      ),
    ];
    return CommonPopScope(
      onPop: isSelecting
          ? (_) {
              ref.read(itemsProvider(_key).notifier).value = {};
              return false;
            }
          : null,
      child: CommonScaffold(
        title: appLocalizations.addedRules,
        searchState: AppBarSearchState(onSearch: _handleSearch),
        actions: [
          if (!isSelecting)
            IconButton(
              tooltip: appLocalizations.add,
              onPressed: _handleAddOrUpdate,
              icon: const GlyphIcon(AppGlyphs.addCircle),
            ),
        ],
        iconActions: [
          if (!isSelecting)
            IconButtonData(
              glyph: AppGlyphs.rulePresets,
              onPressed: _handleQuickActions,
              tooltip: appLocalizations.quickActions,
            ),
        ],
        menuItems: isSelecting
            ? const []
            : [
                CommonPopupMenuItem(
                  glyph: AppGlyphs.importFile,
                  label: appLocalizations.importFile,
                  onPressed: _handleImport,
                ),
                CommonPopupMenuItem(
                  glyph: AppGlyphs.export,
                  label: appLocalizations.exportFile,
                  onPressed: _handleExport,
                ),
              ],
        selectionActions: isSelecting ? selectionActions : const [],
        body: NullStatusSwitcher(
          isLoading: rulesState.isLoading,
          isEmpty: rules.isEmpty,
          isSearching: isSearching,
          nullStatus: NullStatus(
            label: appLocalizations.nullTip(appLocalizations.rule),
            illustration: NullStatusIllustration.rules,
          ),
          child: Builder(
            builder: (context) => isSearching
                ? ListView.builder(
                    padding: _listPadding(context),
                    itemBuilder: (_, index) =>
                        _buildRuleItem(rules, index, selectedRules),
                    itemExtent: ruleItemHeight,
                    itemCount: rules.length,
                  )
                : ReorderableList(
                    padding: _listPadding(context),
                    itemBuilder: (_, index) =>
                        ReorderableDelayedDragStartListener(
                          key: ObjectKey(rules[index]),
                          index: index,
                          child: _buildRuleItem(rules, index, selectedRules),
                        ),
                    proxyDecorator: (child, index, animation) =>
                        commonProxyDecorator(
                          _buildRuleItem(rules, index, selectedRules),
                          index,
                          animation,
                        ),
                    itemExtent: ruleItemHeight,
                    itemCount: rules.length,
                    onReorderItem: (oldIndex, newIndex) => ref
                        .read(globalRulesProvider.notifier)
                        .order(oldIndex, newIndex),
                  ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _listPadding(BuildContext context) => EdgeInsets.fromLTRB(
    16,
    context.contentTopPadding,
    16,
    16 + context.bottomInset,
  );

  Widget _buildRuleItem(List<Rule> rules, int index, Set<dynamic> selected) {
    final rule = rules[index];
    return ItemPositionProvider(
      key: ObjectKey(rule),
      position: ItemPosition.get(index, rules.length),
      child: RuleItem(
        hasMatch: true,
        isEditing: selected.isNotEmpty,
        rule: rule,
        isSelected: selected.contains(rule.id),
        onSelected: () {
          _handleSelected(rule.id);
        },
        onEdit: (Rule rule) {
          _handleAddOrUpdate(rule);
        },
      ),
    );
  }
}
