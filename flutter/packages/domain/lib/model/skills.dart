/// Session-scoped skill catalog (`skill.list`).
library;

/// One user-invocable skill from the session's catalog. Picking a candidate
/// lands the literal `/name ` text in the composer, mirroring the Web
/// client's plain-text-reference decision.
final class SkillEntry {
  const SkillEntry({
    required this.name,
    required this.description,
    this.whenToUse,
    this.modelInvocable = false,
  });

  final String name;
  final String description;
  final String? whenToUse;
  final bool modelInvocable;

  @override
  bool operator ==(Object other) =>
      other is SkillEntry &&
      other.name == name &&
      other.description == description &&
      other.whenToUse == whenToUse &&
      other.modelInvocable == modelInvocable;

  @override
  int get hashCode =>
      Object.hash(name, description, whenToUse, modelInvocable);
}
