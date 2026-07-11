class AuthUser {
  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final String provider; // google | github | apple | demo
  final bool demo;       // shared throwaway demo session (short-lived, resets periodically)
  const AuthUser({required this.id, required this.email, this.name, this.avatarUrl, required this.provider, this.demo = false});

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'] as String,
    email: j['email'] as String,
    name: j['name'] as String?,
    avatarUrl: j['avatar_url'] as String?,
    provider: j['provider'] as String? ?? 'unknown',
    demo: j['demo'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name, 'avatar_url': avatarUrl, 'provider': provider, 'demo': demo};
}
