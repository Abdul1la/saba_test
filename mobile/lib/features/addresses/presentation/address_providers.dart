import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_endpoints.dart';
import '../../../core/errors/result.dart';
import '../../../core/location/governorate.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/json_reader.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/entities.dart';

abstract interface class AddressRepository {
  Future<Result<List<Address>>> fetchAddresses();

  Future<Result<Address>> create(Address address);

  Future<Result<Address>> update(Address address);

  Future<Result<void>> delete(String id);

  Future<Result<void>> setDefault(String id);
}

class AddressMappers {
  const AddressMappers._();

  static Address fromJson(Map<String, dynamic> json) => Address(
    id: Json.str(json, const ['id', 'addressId']),
    fullName: Json.str(json, const ['fullName', 'name', 'recipientName']),
    phone: Json.str(json, const ['phone', 'phoneNumber']),
    governorate: Governorate.fromApi(json['governorate'] ?? json['city']),
    area: Json.str(json, const ['area', 'district']),
    landmark: Json.str(json, const ['landmark', 'nearestLandmark']),
    street: Json.strOrNull(json, const ['street', 'addressLine', 'line1']),
    label: Json.strOrNull(json, const ['label', 'title', 'nickname']),
    instructions: Json.strOrNull(json, const [
      'instructions',
      'deliveryInstructions',
      'notes',
    ]),
    isDefault: Json.boolean(json, const ['isDefault', 'default']),
    latitude: Json.decimalOrNull(json, const ['latitude', 'lat']),
    longitude: Json.decimalOrNull(json, const ['longitude', 'lng', 'lon']),
  );
}

class AddressRepositoryImpl implements AddressRepository {
  const AddressRepositoryImpl(this.client);

  final ApiClient client;

  @override
  Future<Result<List<Address>>> fetchAddresses() {
    return client.get<List<Address>>(
      ApiEndpoints.addresses,
      decoder: (envelope) =>
          Json.mapList(envelope.dataAsList, AddressMappers.fromJson),
    );
  }

  @override
  Future<Result<Address>> create(Address address) {
    return client.post<Address>(
      ApiEndpoints.addresses,
      data: address.toJson(),
      decoder: (envelope) => AddressMappers.fromJson(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<Address>> update(Address address) {
    return client.put<Address>(
      ApiEndpoints.address(address.id),
      data: address.toJson(),
      decoder: (envelope) => AddressMappers.fromJson(envelope.dataAsMap),
    );
  }

  @override
  Future<Result<void>> delete(String id) =>
      client.command(ApiEndpoints.address(id), method: 'DELETE');

  @override
  Future<Result<void>> setDefault(String id) =>
      client.command(ApiEndpoints.defaultAddress(id), method: 'PUT');
}

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  ref.watch(accountIdProvider);
  return AddressRepositoryImpl(ref.watch(apiClientProvider));
});

/// The customer's saved addresses.
class AddressListController extends AsyncNotifier<List<Address>> {
  AddressRepository get _repository => ref.read(addressRepositoryProvider);

  @override
  Future<List<Address>> build() async {
    if (ref.watch(accountIdProvider) == null) return const <Address>[];
    return (await _repository.fetchAddresses()).unwrap();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () async => (await _repository.fetchAddresses()).unwrap(),
    );
  }

  Future<Result<Address>> create(Address address) async {
    final result = await _repository.create(address);
    if (result.isOk) await refresh();
    return result;
  }

  /// Named `edit` rather than `update` because `AsyncNotifier` already defines
  /// an `update` method with a different contract.
  Future<Result<Address>> edit(Address address) async {
    final result = await _repository.update(address);
    if (result.isOk) await refresh();
    return result;
  }

  Future<Result<void>> delete(String id) async {
    final result = await _repository.delete(id);
    if (result.isOk) await refresh();
    return result;
  }

  Future<Result<void>> setDefault(String id) async {
    final result = await _repository.setDefault(id);
    if (result.isOk) await refresh();
    return result;
  }
}

final addressListProvider =
    AsyncNotifierProvider<AddressListController, List<Address>>(
      AddressListController.new,
    );

/// The address checkout should preselect.
final defaultAddressProvider = Provider<Address?>((ref) {
  final addresses = ref.watch(addressListProvider).value;
  if (addresses == null || addresses.isEmpty) return null;
  for (final address in addresses) {
    if (address.isDefault) return address;
  }
  return addresses.first;
});

/// The governorate a parcel would actually go to.
///
/// Every "delivers to ... for ... in ..." line reads this, and so does
/// checkout, because they have to be the same city: a shopper whose profile
/// says Erbil and whose address is in Baghdad was shown Nova's out-of-town
/// price on the product page and charged its in-town price at checkout -
/// two true answers to one question.
///
/// Falls back to the city they shop from, for someone who has not saved an
/// address yet.
final deliveryCityProvider = Provider<Governorate?>(
  (ref) =>
      ref.watch(defaultAddressProvider)?.governorate ??
      ref.watch(shopperCityProvider),
);
