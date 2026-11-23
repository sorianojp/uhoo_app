import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../theme.dart';
import '../data/polling.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'saved_screen.dart';
import 'message_media.dart';
import 'widgets.dart';
import 'conversation_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final SessionController session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<Conversation> _conversations = [];
  int _tab = 0;
  String _filter = 'All';
  int? _next;
  bool _loading = true;
  bool _fetching = false;
  Future<void>? _inflight;
  Object? _error;
  Timer? _poll;
  DateTime _lastRefresh = DateTime.now();
  Timer? _debounce;
  StreamSubscription<Json>? _events;
  SessionController get session => widget.session;
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '[ui] HomeScreen mounted (team ${session.team?.slug}, '
        'session #${identityHashCode(session)})',
      );
    }
    if (session.team != null) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 25), (_) {
        if (!session.foreground) return;
        // Polling also discovers new conversations and sends the presence
        // heartbeat (contacts show as online for 3 minutes after the last one).
        if (PollingPolicy.shouldPoll(
          realtimeLive: session.realtime?.isConnected ?? false,
          lastRefresh: _lastRefresh,
          now: DateTime.now(),
        )) {
          _lastRefresh = DateTime.now();
          _load();
          _presence();
        }
      });
      _presence();
      _events = session.realtime?.events.listen((event) {
        if (event['event'] == 'client-typing' ||
            event['event'] == 'subscribed') {
          return;
        }
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 450), () => _load());
      });
    } else {
      _loading = false;
    }
  }

  Future<void> _presence() async {
    try {
      await session.api.request('POST', '${session.teamPath}/presence');
    } catch (_) {
      /* Inbox reports connection errors. */
    }
  }

  Future<void> _load({bool more = false, bool reset = false}) async {
    if (session.team == null) return;
    final inflight = _inflight;
    if (inflight != null) {
      // A background poll must not swallow a refresh the user just triggered:
      // skip a duplicate poll, but queue anything that has to be seen.
      if (!reset && !more) return;
      await inflight;
      if (!mounted) return;
    }
    final request = _fetch(more: more, reset: reset);
    _inflight = request;
    try {
      await request;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _fetch({required bool more, required bool reset}) async {
    _fetching = true;
    final page = more ? _next : 1;
    final archived = _filter == 'Archived';
    try {
      final data = PageData.from(
        await session.api.request(
          'GET',
          '${session.teamPath}/conversations?page=$page&archived=${archived ? 1 : 0}',
        ),
        Conversation.new,
      );
      if (!mounted) return;
      setState(() {
        if (reset || (page == 1 && _next == 2)) {
          _conversations = data.items;
        } else if (more) {
          final items = {
            for (final c in _conversations) c.id: c,
            for (final c in data.items) c.id: c,
          };
          _conversations = items.values.toList();
        } else {
          // The first page is authoritative about what belongs in this list, so
          // anything it no longer returns (archived elsewhere, or left) is
          // dropped rather than kept forever by the merge.
          final incoming = data.items.map((c) => c.id).toSet();
          final firstPage = data.items.length;
          _conversations = [
            ...data.items,
            ..._conversations
                .skip(firstPage)
                .where((c) => !incoming.contains(c.id)),
          ];
        }
        if (more || reset || _conversations.length <= 25) _next = data.next;
        _error = null;
      });
      for (final conversation in data.items) {
        session.realtime?.subscribe('private-conversations.${conversation.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Conversation conversation, {int? messageId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/conversations/${conversation.id}'),
        builder: (_) => ChatScreen(
          session: session,
          conversation: conversation,
          initialMessageId: messageId,
        ),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  Future<void> _openSaved() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SavedScreen(
        session: session,
        onOpen: (id, messageId) async {
          final data = await session.api.request(
            'GET',
            '${session.teamPath}/conversations/$id',
          );
          if (mounted) {
            await _open(
              Conversation(data['data'] as Json),
              messageId: messageId,
            );
          }
        },
      ),
    ),
  );

  Future<void> _compose() async {
    final result = await Navigator.push<Conversation>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactsScreen(session: session, selecting: true),
      ),
    );
    if (result != null && mounted) await _open(result);
  }

  Future<void> _conversationMenu(Conversation conversation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                conversation.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(
                conversation.pinned ? 'Unpin conversation' : 'Pin conversation',
              ),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(
                conversation.muted
                    ? 'Unmute conversation'
                    : 'Mute conversation',
              ),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(
                conversation.archived
                    ? 'Move to inbox'
                    : 'Archive conversation',
              ),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            if (conversation.archived)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete conversation'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'delete') {
      await _delete(conversation);
      return;
    }
    final fields = {
      'pin': {'pinned': !conversation.pinned},
      'mute': {'muted': !conversation.muted},
      'archive': {'archived': !conversation.archived},
    };
    try {
      final response = await session.api.request(
        'PATCH',
        '${session.teamPath}/conversations/${conversation.id}/$action',
        body: fields[action],
      );
      if (!mounted) return;
      setState(() {
        // The server returns the new pivot timestamps; apply them so the row
        // updates on the spot instead of waiting for the next poll.
        final data = response['data'];
        if (data is Map) {
          conversation.json.addAll(Map<String, dynamic>.from(data));
        }
        if (action == 'archive') {
          // The inbox and the archive are mutually exclusive, so the
          // conversation leaves whichever list is on screen.
          _conversations = _conversations
              .where((c) => c.id != conversation.id)
              .toList();
        } else if (action == 'pin') {
          _sort();
        }
      });
      await _load(reset: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Removes an archived conversation from this account, as on the web.
  Future<void> _delete(Conversation conversation) async {
    if (!await confirmAction(
      context,
      'Delete conversation?',
      'This removes ${conversation.name} from your archive. Other members keep their copy.',
      'Delete',
    )) {
      return;
    }
    try {
      await session.api.request(
        'DELETE',
        '${session.teamPath}/conversations/${conversation.id}',
      );
      if (!mounted) return;
      session.drafts.remove(conversation.id);
      setState(() {
        _conversations = _conversations
            .where((c) => c.id != conversation.id)
            .toList();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Mirrors the server ordering: pinned first, then most recent.
  void _sort() {
    _conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final left = a.updated;
      final right = b.updated;
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
  }

  Widget _inbox(double bottomInset) {
    final query = _search.text.toLowerCase();
    final me = session.user!.id;
    final conversations = _conversations
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) &&
              (_filter != 'Unread' || c.unread > 0) &&
              (_filter != 'Groups' || c.group),
        )
        .toList();
    // Messenger's "active now" row: direct chats whose other person is online.
    final active = _filter == 'All' && query.isEmpty
        ? _conversations
              .where(
                (c) =>
                    !c.group &&
                    c.participants.any((p) => p.id != me && p.online),
              )
              .take(20)
              .toList()
        : const <Conversation>[];
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: pillSearchDecoration(context, 'Search'),
              ),
            ),
          ),
          if (active.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: active.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) => _ActivePerson(
                    session: session,
                    conversation: active[index],
                    onTap: () => _open(active[index]),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in ['All', 'Unread', 'Groups', 'Archived'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: _fetching
                            ? null
                            : (_) {
                                final changed =
                                    (_filter == 'Archived') !=
                                    (filter == 'Archived');
                                setState(() {
                                  _filter = filter;
                                  if (changed) {
                                    _conversations = [];
                                    _loading = true;
                                  }
                                });
                                if (changed) _load(reset: true);
                              },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          if (_error != null && _conversations.isNotEmpty)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: const Text(
                  'Could not refresh messages. Pull down to retry.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => _load(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _conversations.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Unable to load messages',
                message: _error.toString(),
                action: FilledButton(
                  onPressed: () => _load(reset: true),
                  child: const Text('Try again'),
                ),
              ),
            )
          else if (conversations.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: query.isNotEmpty
                    ? 'No matching conversations'
                    : _filter == 'Unread'
                    ? 'You’re all caught up'
                    : _filter == 'Archived'
                    ? 'No archived conversations'
                    : 'Start a conversation',
                message: query.isNotEmpty
                    ? 'Try a different name or load more conversations.'
                    : 'Keep in touch with your school community.',
                action: _filter == 'All' && query.isEmpty
                    ? FilledButton.icon(
                        onPressed: _compose,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('New message'),
                      )
                    : null,
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final c = conversations[index];
                return _ConversationRow(
                  session: session,
                  conversation: c,
                  onTap: () => _open(c),
                  onLongPress: () => _conversationMenu(c),
                );
              },
            ),
            if (_next != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: _fetching ? null : () => _load(more: true),
                    child: const Text('Load more conversations'),
                  ),
                ),
              ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: 24 + bottomInset)),
        ],
      ),
    );
  }

  Widget _settings(double bottomInset) {
    final user = session.user!;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
        Center(child: PersonAvatar(user.name, size: 96, brand: true)),
        const SizedBox(height: 14),
        Text(
          user.name,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (user.role.isNotEmpty)
          Center(
            child: Chip(
              label: Text(user.role[0].toUpperCase() + user.role.substring(1)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        const SizedBox(height: 20),
        _SettingsGroup(
          title: 'Account',
          children: [
            _SettingsRow(
              icon: Icons.apartment_rounded,
              title: 'Department',
              subtitle: user.department?.label ?? 'Not assigned in STEP',
            ),
            _SettingsRow(
              icon: Icons.badge_rounded,
              title: 'STEP roles',
              subtitle: user.stepRoles.isEmpty
                  ? 'No roles synchronized yet'
                  : user.stepRoles.join(', '),
            ),
            if (session.stepAccountUrl != null)
              _SettingsRow(
                icon: Icons.manage_accounts_rounded,
                title: 'Manage account in STEP',
                subtitle:
                    'Change your name, email, password, or role. Uhoo! refreshes them on your next sign-in.',
                trailing: Icons.open_in_new_rounded,
                onTap: () => openExternalLink(context, session.stepAccountUrl!),
              ),
            _SettingsRow(
              icon: Icons.school_rounded,
              title: 'School workspace',
              subtitle: session.team?.name ?? 'No workspace',
              onTap: _chooseTeam,
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Preferences',
          children: [
            _SettingsRow(
              icon: Icons.bookmark_rounded,
              title: 'Saved messages',
              subtitle: 'Messages you saved to find later',
              onTap: _openSaved,
            ),
            _SettingsRow(
              icon: Icons.dark_mode_rounded,
              title: 'Appearance',
              subtitle: switch (session.themeMode) {
                ThemeMode.system => 'Use device settings',
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
              },
              onTap: _chooseAppearance,
            ),
          ],
        ),
        _SettingsGroup(
          title: 'Support',
          children: [
            _SettingsRow(
              icon: Icons.help_rounded,
              title: 'Help and support',
              subtitle: 'Contact Uhoo! support',
              trailing: Icons.open_in_new_rounded,
              onTap: () => openSupportPage(context),
            ),
            // The version comes from the app bundle (pubspec.yaml's `version`).
            FutureBuilder<PackageInfo>(
              future: _packageInfo,
              builder: (context, snapshot) {
                final version = snapshot.data == null
                    ? ''
                    : '${snapshot.data!.version} (${snapshot.data!.buildNumber})';
                return _SettingsRow(
                  icon: Icons.info_rounded,
                  title: 'About Uhoo!',
                  subtitle: version.isEmpty ? 'Uhoo!' : 'Version $version',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Uhoo!',
                    applicationVersion: version,
                    applicationIcon: const Icon(Icons.school_rounded, size: 40),
                    children: [
                      const Text(
                        'A place for your school community to stay connected.',
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            if (!await confirmAction(
              context,
              'Sign out?',
              'You can sign in again with your STEP account.',
              'Sign out',
            )) {
              return;
            }
            try {
              await session.signOut();
            } catch (e) {
              if (mounted) showError(context, e);
            }
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Future<void> _chooseAppearance() async {
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(
                  mode == ThemeMode.system
                      ? 'Use device settings'
                      : mode == ThemeMode.light
                      ? 'Light'
                      : 'Dark',
                ),
                trailing: session.themeMode == mode
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (mode != null) await session.setTheme(mode);
  }

  Future<void> _chooseTeam() async {
    final selected = await showModalBottomSheet<Team>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Your workspaces',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final team in session.teams)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(team.name),
                trailing: team.id == session.team?.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, team),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await session.selectTeam(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (session.team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Uhoo!')),
        body: EmptyState(
          icon: Icons.school_outlined,
          title: 'Your school is not connected yet',
          message: 'Ask your school to add your STEP account to a workspace.',
          action: TextButton(
            onPressed: session.signOut,
            child: const Text('Sign out'),
          ),
        ),
      );
    }
    final unread = _conversations.fold<int>(0, (total, c) => total + c.unread);
    final colors = Theme.of(context).colorScheme;
    final pageTitle = switch (_tab) {
      0 => _filter == 'Archived' ? 'Archived' : 'Chat',
      1 => 'People',
      _ => 'Profile',
    };
    // Messenger-style: one flat surface from header to tab bar.
    final surface = colors.surfaceContainerLow;
    return Scaffold(
      extendBody: true,
      backgroundColor: surface,
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        backgroundColor: surface,
        shape: const Border(),
        title: Row(
          children: [
            Tooltip(
              message: 'Profile',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _tab = 2),
                child: PersonAvatar(session.user!.name, size: 36, brand: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pageTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  GestureDetector(
                    onTap: _chooseTeam,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            session.team!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_tab == 0 && _filter != 'Archived')
            _CircleAction(
              tooltip: 'New message',
              icon: Icons.edit_square,
              onPressed: _compose,
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: switch (_tab) {
            0 => _inbox(_HomeNavigationBar.clearance),
            1 => ContactsScreen(
              session: session,
              onOpen: _open,
              bottomInset: _HomeNavigationBar.clearance,
            ),
            _ => _settings(_HomeNavigationBar.clearance),
          },
        ),
      ),
      bottomNavigationBar: _HomeNavigationBar(
        selectedIndex: _tab,
        unread: unread,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _events?.cancel();
    _search.dispose();
    super.dispose();
  }
}

/// A titled card of settings rows, like Messenger's settings sections.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(StepShape.radiusLarge),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      shape: const RoundedRectangleBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: colors.onPrimary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null
          ? null
          : Icon(
              trailing ?? Icons.chevron_right_rounded,
              size: trailing == null ? 22 : 18,
              color: colors.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }
}

/// The round, muted header button Messenger uses for "new message".
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.surfaceContainerHigh,
        foregroundColor: colors.onSurface,
        fixedSize: const Size(40, 40),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 20, color: colors.onSurface),
    );
  }
}

/// A person in the "active now" row above the inbox.
class _ActivePerson extends StatelessWidget {
  const _ActivePerson({
    required this.session,
    required this.conversation,
    required this.onTap,
  });
  final SessionController session;
  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final firstName = conversation.name.trim().split(RegExp(r'[\s,]+')).first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StepShape.radiusLarge),
      child: SizedBox(
        width: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ConversationAvatar(
                session: session,
                conversation: conversation,
                size: 56,
                online: true,
              ),
              const SizedBox(height: 6),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modern iOS Facebook Messenger-style floating frosted-glass pill tab bar:
/// translucent capsule with sliding active pill highlight, solid filled icons,
/// cutout red unread badge, and subtle spring tap bounce.
class _HomeNavigationBar extends StatelessWidget {
  const _HomeNavigationBar({
    required this.selectedIndex,
    required this.unread,
    required this.onDestinationSelected,
  });

  /// Scrollable bottom clearance so content clears the floating capsule.
  static const clearance = 78.0;

  final int selectedIndex;
  final int unread;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    (label: 'Chat', tooltip: 'Messages', icon: Icons.chat_bubble_rounded),
    (label: 'People', tooltip: 'People', icon: Icons.people_alt_rounded),
    (label: 'Profile', tooltip: 'Profile', icon: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glassFill = dark
        ? StepPalette.cardDark.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.80);
    final glassBorder = dark
        ? Colors.white.withValues(alpha: 0.14)
        : colors.outlineVariant.withValues(alpha: 0.55);
    final activePillColor = dark
        ? Colors.white.withValues(alpha: 0.13)
        : StepPalette.secondary.withValues(alpha: 0.90);
    final badgeRingBase = dark ? StepPalette.cardDark : Colors.white;
    final pillAlignmentX = _destinations.length <= 1
        ? 0.0
        : -1.0 + (2.0 * selectedIndex / (_destinations.length - 1));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 264),
            child: DecoratedBox(
              key: const ValueKey('ios-glass-navbar'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(StepShape.radiusPill),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.36 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.20 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(StepShape.radiusPill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: glassFill,
                      borderRadius: BorderRadius.circular(StepShape.radiusPill),
                      border: Border.all(color: glassBorder, width: 1),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment(pillAlignmentX, 0),
                            child: FractionallySizedBox(
                              widthFactor: 1 / _destinations.length,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: activePillColor,
                                  borderRadius: BorderRadius.circular(
                                    StepShape.radiusPill,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _destinations.length; i++)
                              Expanded(
                                child: _HomeNavigationItem(
                                  label: _destinations[i].label,
                                  tooltip: _destinations[i].tooltip,
                                  icon: _destinations[i].icon,
                                  selected: i == selectedIndex,
                                  badge: i == 0 ? unread : 0,
                                  badgeRingColor: i == selectedIndex
                                      ? (dark
                                            ? StepPalette.secondaryDark
                                            : StepPalette.secondary)
                                      : badgeRingBase,
                                  onTap: () => onDestinationSelected(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavigationItem extends StatefulWidget {
  const _HomeNavigationItem({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.badge,
    required this.badgeRingColor,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final int badge;
  final Color badgeRingColor;
  final VoidCallback onTap;

  @override
  State<_HomeNavigationItem> createState() => _HomeNavigationItemState();
}

class _HomeNavigationItemState extends State<_HomeNavigationItem> {
  static const _messengerBadgeRed = Color(0xFFFA383E);
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = widget.selected
        ? brandText(context)
        : colors.onSurfaceVariant.withValues(alpha: 0.78);
    final badgeText = widget.badge > 99 ? '99+' : '${widget.badge}';

    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.88 : 1.0,
              duration: Duration(milliseconds: _pressed ? 80 : 180),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, color: foreground, size: 26),
                  if (widget.badge > 0)
                    Positioned(
                      top: -5,
                      right: widget.badge > 9 ? -12 : -8,
                      child: Container(
                        key: const ValueKey('nav-unread-badge'),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.badge > 9 ? 5 : 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: _messengerBadgeRed,
                          borderRadius: BorderRadius.circular(
                            StepShape.radiusPill,
                          ),
                          border: Border.all(
                            color: widget.badgeRingColor,
                            width: 1.75,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A conversation in the inbox, Messenger-style: large avatar, bold name and
/// preview while unread, and the time after the preview.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.session,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });
  final SessionController session;
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final colors = Theme.of(context).colorScheme;
    final me = session.user!.id;
    final other = c.participants.where((p) => p.id != me).firstOrNull;
    final draft = session.drafts[c.id]?.trim() ?? '';
    final unread = c.unread > 0;
    final preview = draft.isNotEmpty
        ? 'Draft: $draft'
        : '${c.latest?.sender?.id == me && c.latest?.unsent == false ? 'You: ' : ''}${c.latest?.preview ?? 'No messages yet'}';
    final time = timeLabel(c.updated);
    final previewStyle = TextStyle(
      fontSize: 13,
      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
      color: unread ? colors.onSurface : colors.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ConversationAvatar(
              session: session,
              conversation: c,
              size: 56,
              online: !c.group && (other?.online ?? false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: draft.isNotEmpty
                              ? previewStyle.copyWith(color: brandText(context))
                              : previewStyle,
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(' · $time', style: previewStyle),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.pinned)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                      semanticLabel: 'Pinned',
                    ),
                  ),
                if (c.muted)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.notifications_off_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                      semanticLabel: 'Muted',
                    ),
                  ),
                if (c.unreadMentions > 0) ...[
                  const SizedBox(width: 6),
                  const _CountBadge(
                    label: '@',
                    semantics: 'Unread mention',
                    muted: true,
                  ),
                ],
                if (unread) ...[
                  const SizedBox(width: 6),
                  _CountBadge(
                    label: c.unread > 99 ? '99+' : '${c.unread}',
                    semantics: '${c.unread} unread',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 20px round unread (and @mention) badge from the web inbox.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.semantics,
    this.muted = false,
  });
  final String label;
  final String semantics;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? colors.surfaceContainerHigh : colors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: muted ? 11 : 10,
            fontWeight: FontWeight.w600,
            color: muted ? colors.onSurface : colors.onPrimary,
          ),
        ),
      ),
    );
  }
}
