import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/services/groq_service.dart';

/// Neo-Graphic Flowchart & Diagram Widget
///
/// Renders structured flow diagrams and architecture steps directly in Flutter
/// without external heavy libraries, keeping app size extremely light.
class BuddyFlowchartWidget extends StatelessWidget {
  final FlowchartData data;

  const BuddyFlowchartWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BuddyColors.bone,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BuddyColors.pitch, width: 2),
        boxShadow: const [
          BoxShadow(
            color: BuddyColors.pitch,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Diagram Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: BuddyColors.lime,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                ),
                child: const Icon(Icons.account_tree_rounded, size: 16, color: BuddyColors.onLime),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FLOW DIAGRAM',
                      style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.smoke),
                    ),
                    Text(
                      data.title,
                      style: BuddyTheme.displayFont(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: BuddyColors.carbon,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Flowchart Steps
          Column(
            children: List.generate(data.steps.length, (index) {
              final isLast = index == data.steps.length - 1;
              final step = data.steps[index];

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Node index badge
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? BuddyColors.lime
                              : (isLast ? BuddyColors.carbon : Colors.white),
                          shape: BoxShape.circle,
                          border: Border.all(color: BuddyColors.pitch, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: index == 0
                                  ? BuddyColors.onLime
                                  : (isLast ? Colors.white : BuddyColors.carbon),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Node content card
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: BuddyColors.pitch, width: 1.5),
                            boxShadow: const [
                              BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 1.5)),
                            ],
                          ),
                          child: Text(
                            step,
                            style: BuddyTheme.bodyFont(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BuddyColors.carbon,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Connector line and arrow
                  if (!isLast)
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      alignment: Alignment.centerLeft,
                      child: Column(
                        children: [
                          Container(
                            width: 2,
                            height: 14,
                            color: BuddyColors.carbon,
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 14,
                            color: BuddyColors.carbon,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

