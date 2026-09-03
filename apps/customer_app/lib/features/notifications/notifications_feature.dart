part of '../../main.dart';

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({
    required this.repository,
    required this.audience,
    required this.onPressed,
  });

  final PlatformRepository repository;
  final String audience;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: repository.watchUnreadNotificationCount(audience: audience),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

class _NotificationsPage extends StatefulWidget {
  const _NotificationsPage({
    required this.repository,
    required this.audience,
  });

  final PlatformRepository repository;
  final String audience;

  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  final Set<String> _readRequests = <String>{};

  void _markVisibleRead(List<UserNotification> notifications) {
    final unread = notifications.where((item) => !item.isRead);
    for (final notification in unread) {
      if (_readRequests.add(notification.id)) {
        scheduleMicrotask(
          () => widget.repository.markNotificationRead(notification.id),
        );
      }
    }
  }

  Future<void> _showNotificationActions(UserNotification notification) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mark_email_read_outlined),
              title: const Text('Mark as read'),
              enabled: !notification.isRead,
              onTap: () => Navigator.of(context).pop('read'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'read') {
        await widget.repository.markNotificationRead(notification.id);
      } else if (action == 'delete') {
        await widget.repository.deleteNotification(notification.id);
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Notification update failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<UserNotification>>(
        stream: widget.repository.watchMyNotifications(
          audience: widget.audience,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineState(
              title: 'Notifications failed to load',
              message: '${snapshot.error}',
            );
          }

          final notifications = snapshot.data ?? const <UserNotification>[];
          _markVisibleRead(notifications);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: notifications.any((item) => !item.isRead)
                          ? widget.repository.markAllNotificationsRead
                          : null,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Read all'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: notifications.isEmpty
                    ? const Center(child: Text('No notifications yet'))
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return ListTile(
                            leading: Icon(
                              notification.isRead
                                  ? Icons.notifications_none
                                  : Icons.notifications_active_outlined,
                            ),
                            title: Text(notification.title),
                            subtitle: Text(
                              [
                                if (notification.body.isNotEmpty)
                                  notification.body,
                                _formatDateTime(notification.createdAt),
                              ].join('\n'),
                            ),
                            isThreeLine: notification.body.isNotEmpty,
                            trailing: notification.isRead
                                ? null
                                : IconButton(
                                    tooltip: 'Mark read',
                                    icon: const Icon(
                                      Icons.mark_email_read_outlined,
                                    ),
                                    onPressed: () =>
                                        widget.repository.markNotificationRead(
                                      notification.id,
                                    ),
                                  ),
                            onLongPress: () =>
                                unawaited(_showNotificationActions(
                              notification,
                            )),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
