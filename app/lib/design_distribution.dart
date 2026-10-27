import 'dart:io';

const designAppName = 'Wallet APS Design';
const designReleasesUrl =
    'https://github.com/lc200333-cmyk/Wallet-APS-Design/releases';

/// Never reuse or migrate the stable application's profile implicitly.
Directory designSupportDirectory(Directory platformSupport) =>
    Directory('${platformSupport.path}${Platform.pathSeparator}$designAppName');
