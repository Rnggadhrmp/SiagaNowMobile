class DonationCampaign {
  const DonationCampaign({
    required this.id,
    required this.title,
    required this.slug,
    required this.description,
    required this.organizer,
    required this.targetAmount,
    required this.sourceName,
    required this.sourceUrl,
    required this.verifiedAt,
  });

  final int id;
  final String title;
  final String slug;
  final String description;
  final String organizer;
  final int? targetAmount;
  final String sourceName;
  final Uri? sourceUrl;
  final DateTime? verifiedAt;

  bool get isVerified => verifiedAt != null;

  factory DonationCampaign.fromJson(Map<String, dynamic> json) {
    final id = int.tryParse('${json['id'] ?? ''}');
    if (id == null) {
      throw const FormatException('ID program donasi tidak valid.');
    }
    final source = json['source_url']?.toString();
    final target = json['target_amount'];
    return DonationCampaign(
      id: id,
      title: json['title']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      organizer: json['organizer']?.toString() ?? '',
      targetAmount: target == null ? null : int.tryParse('$target'),
      sourceName: json['source_name']?.toString() ?? '',
      sourceUrl: source == null || source.isEmpty ? null : Uri.tryParse(source),
      verifiedAt: DateTime.tryParse(json['verified_at']?.toString() ?? ''),
    );
  }
}
