import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../content/presentation/bloc/content_bloc.dart';
import '../../../content/presentation/bloc/content_event.dart';
import '../../../content/presentation/bloc/content_state.dart';
import '../../../../core/utils/logout_helper.dart';
import '../../../../core/utils/admin_actions_bottom_sheet.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/widgets/offline_aware_image.dart';
import '../../../organization/presentation/widgets/create_organization_sheet.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late ContentBloc _contentBloc;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    _contentBloc.add(const ContentEvent.getWorlds());
  }

  @override
  void dispose() {
    _contentBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة العوالم'),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => showLogoutBottomSheet(
                context,
                onCreateOrganization: () => showCreateOrganizationSheet(context),
              ),
            ),
          ],
        ),
        body: BlocBuilder<ContentBloc, ContentState>(
          builder: (context, state) {
            return state.maybeWhen(
              loading: () => const ShimmerLoading(),
              error: (msg) => Center(child: Text('خطأ: $msg', style: const TextStyle(color: Colors.red))),
              worldsLoaded: (worlds) {
                if (worlds.isEmpty) {
                  return const Center(child: Text('لا توجد عوالم مضافة حتى الآن. أضف عالمك الأول!'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _contentBloc.add(const ContentEvent.getWorlds(forceRefresh: true));
                    // Optional: wait a bit for the bloc to process
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: worlds.length,
                    itemBuilder: (context, index) {
                      final world = worlds[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppColors.border_radius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Background Image
                            if (world.imageUrl.isNotEmpty)
                              OfflineAwareImage(
                                imageUrl: world.imageUrl,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  height: 180,
                                  width: double.infinity,
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  child: const Icon(Icons.broken_image, size: 64, color: Colors.white54),
                                ),
                              )
                            else
                              Container(
                                height: 180,
                                width: double.infinity,
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.public, size: 64, color: Colors.white54),
                              ),
                          // Gradient Overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ),
                          ),
                          // Content
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        world.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        world.description,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 14,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      // Badges
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(AppColors.border_radius),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.explore, color: Colors.white, size: 14),
                                                SizedBox(width: 4),
                                                Text('عالم استكشافي', style: TextStyle(color: Colors.white, fontSize: 10)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(AppColors.border_radius),
                                            ),
                                            child: const Row(
                                              children: [
                                                Icon(Icons.star, color: Colors.amber, size: 14),
                                                SizedBox(width: 4),
                                                Text('مغامرة ممتعة', style: TextStyle(color: Colors.white, fontSize: 10)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Ripple Effect
                          Positioned.fill(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  context.push('/admin/world-missions', extra: world);
                                },
                              ),
                            ),
                          ),
                          // Three dots for actions
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              onPressed: () {
                                showAdminActionsBottomSheet(
                                  context: context,
                                  onEdit: () {
                                    context.push('/admin/add-world', extra: world);
                                  },
                                  onDelete: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('تأكيد الحذف'),
                                        content: const Text('هل أنت متأكد من حذف هذا العالم؟ سيتم حذف جميع المهام والقصص المرتبطة به.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              _contentBloc.add(ContentEvent.deleteWorld(world.id));
                                            },
                                            child: const Text('حذف', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
            orElse: () => const SizedBox(),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            HapticFeedback.lightImpact();
            final result = await context.push('/admin/add-world');
            if (result == true) {
              _contentBloc.add(const ContentEvent.getWorlds());
            }
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
