enum PermissionDecision { allow, deny }

class PermissionDialog {
  const PermissionDialog();

  Future<PermissionDecision> requestTutorialPermission() async {
    throw UnimplementedError('Day 3: implement native Allow/Deny dialog');
  }
}
