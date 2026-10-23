class UserModel {
  final int id;
  final String name;
  final String surname;
  final String email;
  final String? avatar;
  final String? plan;
  final int? credits;
  final String? userType;

  UserModel({
    required this.id,
    required this.name,
    required this.surname,
    required this.email,
    this.avatar,
    this.plan,
    this.credits,
    this.userType,
  });

  String get fullName {
    final full = '$name $surname'.trim();
    return full.isNotEmpty ? full : email.split('@').first;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'surname': surname,
    'email': email,
    'avatar': avatar,
    'plan': plan,
    'credits': credits,
    'type': userType,
  };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    int parsedCredits = 0;
    if (json['remaining_words'] != null) {
      parsedCredits = (double.tryParse(json['remaining_words'].toString()) ?? 0)
          .toInt();
    } else if (json['credits'] != null) {
      parsedCredits = (int.tryParse(json['credits'].toString()) ?? 0);
    }

    return UserModel(
      id: json['id'] is int
          ? json['id']
          : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      name: json['name']?.toString() ?? '',
      surname: json['surname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      plan:
          json['plan']?.toString() ??
          (json['type'] == 'super_admin' ? 'Administrator' : 'Free'),
      credits: parsedCredits,
      userType: json['type']?.toString() ?? 'user',
    );
  }
}
