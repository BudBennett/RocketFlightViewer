import 'package:flutter/material.dart';

/// Secondary/hint text color. Dark mode keeps the original Colors.grey (already
/// good contrast); light mode uses a darker shade since plain grey-on-white read
/// as faded.
Color secondaryTextColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[700]!;
