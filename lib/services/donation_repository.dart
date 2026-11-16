import '../models/donation_campaign.dart';

abstract interface class DonationRepository {
  Future<List<DonationCampaign>> loadCampaigns();
}

class ApiDonationRepository implements DonationRepository {
  const ApiDonationRepository({required this.fetchCampaigns});

  final Future<Map<String, dynamic>> Function() fetchCampaigns;

  @override
  Future<List<DonationCampaign>> loadCampaigns() async {
    final response = await fetchCampaigns();
    final data = response['data'];
    if (data is! List) {
      throw const FormatException('Daftar program donasi tidak valid.');
    }
    return data
        .whereType<Map>()
        .map(
          (value) =>
              DonationCampaign.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false);
  }
}
