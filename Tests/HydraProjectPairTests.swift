import Foundation
import Testing

// Tests for the project rule: the pair that each new chat in a project starts on.
// `HydraPair.projectPair` is the pure part of the rule. `AppModel.newThread` calls it and
// applies the result. Run with `scripts/test_hydra_project_pair.sh`.

private func pair(_ provider: ProviderKind, lead: String? = nil) -> HydraPair {
    var pair = HydraPair(provider: provider)
    pair.orchestratorModel = lead
    return pair
}

@Test func projectPairIsNilWhenHydraIsOff() {
    let chosen = pair(.claude, lead: "opus")
    #expect(HydraPair.projectPair(chosen.id, hydraOn: false, in: [chosen]) == nil)
}

@Test func projectPairIsNilWhenTheProjectHasNoRule() {
    let chosen = pair(.claude, lead: "opus")
    #expect(HydraPair.projectPair(nil, hydraOn: true, in: [chosen]) == nil)
}

@Test func projectPairIsNilWhenThePairIsNotAvailable() {
    let chosen = pair(.claude, lead: "opus")
    let other = pair(.codex, lead: "gpt-6-astra")
    #expect(HydraPair.projectPair(chosen.id, hydraOn: true, in: [other]) == nil)
    #expect(HydraPair.projectPair(chosen.id, hydraOn: true, in: []) == nil)
}

@Test func projectPairIsTheNamedPairWhenItIsAvailable() {
    let chosen = pair(.claude, lead: "opus")
    let other = pair(.codex, lead: "gpt-6-astra")
    let found = HydraPair.projectPair(chosen.id, hydraOn: true, in: [other, chosen])
    #expect(found == chosen)
    #expect(found?.provider == .claude)
}

@Test func pairWithoutTheNewFieldsStillDecodes() throws {
    // A pair saved by an older build has no cap and no efforts. It must decode as before.
    let json = #"{"id":"8CCAAD1F-BA41-46A8-9974-23BEC82A4DDE","provider":"claude","orchestratorModel":"opus"}"#
    let pair = try JSONDecoder().decode(HydraPair.self, from: Data(json.utf8))
    #expect(pair.orchestratorModel == "opus")
    #expect(pair.maxHeads == nil)
    #expect(HydraPair.projectPair(pair.id, hydraOn: true, in: [pair]) == pair)
}
