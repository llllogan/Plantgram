import SwiftUI

struct HouseholdOnboardingSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var isCreating = false
    @State private var householdName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "house.and.flag.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text("You are not part of a household")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        if !isCreating {
                            Text("Would you like to create or join one?")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.top, 24)

                if isCreating {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Household Name")
                            .font(.headline)

                        TextField("Home", text: $householdName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .padding(14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.28), lineWidth: 1)
                            }
                            .onSubmit {
                                createHousehold()
                            }
                    }
                    .padding(.horizontal, 2)
                }

                if let message = sessionStore.householdError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    if isCreating {
                        
                        Button {
                            isCreating = false
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.glass)
                        .disabled(sessionStore.isCreatingHousehold)
                        
                        Button {
                            createHousehold()
                        } label: {
                            Label(
                                sessionStore.isCreatingHousehold ? "Creating..." : "Create Household",
                                systemImage: "plus"
                            )
                            .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.green)
                        .disabled(sessionStore.isCreatingHousehold)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                sessionStore.chooseJoinHousehold()
                            } label: {
                                Label("Join", systemImage: "person.2.badge.plus")
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.glass)

                            Button {
                                isCreating = true
                            } label: {
                                Label("Create", systemImage: "plus")
                                    .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.glass)
                            .tint(.green)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(24)
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private func createHousehold() {
        Task {
            await sessionStore.createHousehold(named: householdName)
        }
    }
}

struct HouseholdOnboardingSheet_Previews: PreviewProvider {
    static var previews: some View {
        HouseholdOnboardingSheet()
            .environmentObject(SessionStore.previewNeedsHousehold)
    }
}
