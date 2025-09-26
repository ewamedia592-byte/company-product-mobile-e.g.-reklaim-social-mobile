cat > lib/models/ewa_user.dart << 'EOF'
class EwaUser {
  final String? uid;
  final String? email;

  EwaUser({this.uid, this.email});
}
EOF