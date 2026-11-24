import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'src/app.dart';
import 'src/data/push_notifications.dart';
import 'src/data/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final imagePicker = ImagePickerPlatform.instance;
  if (imagePicker is ImagePickerAndroid) {
    // Use Android's system Photo Picker so gallery opens directly without
    // requesting READ_MEDIA_* storage permissions.
    imagePicker.useAndroidPhotoPicker = true;
  }
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [('Google Sans', 'OFL-GoogleSans.txt')]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  final pushNotifications = PushNotificationService();
  final session = SessionController(pushNotifications: pushNotifications);

  runApp(UhooApp(session: session));
  await pushNotifications.initialize().timeout(
    const Duration(seconds: 10),
    onTimeout: () => debugPrint('[startup] push initialization timed out'),
  );
  session.restore();
}
