import 'app_user_model.dart';

class CustomerModel extends AppUserModel {

  CustomerModel({
    required super.id,
    required super.name,
    required super.email,
    required super.phoneNumber,
    required super.isActive,
    required super.role,
    required super.createdAt,
    required super.pincode,
    super.profileImageUrl,
    super.address,
    super.city,
    super.state,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      isActive: map['isActive'] ?? false,
      role: map['role'] ?? 'customer',
      createdAt:
      DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      pincode: map['pincode'] ?? '',
      profileImageUrl: map['profileImageUrl'],
      address: map['address'],
      city: map['city'],
      state: map['state'],
    );
  }
}