import Foundation

struct AccountService: Sendable {
    var fetchMeHandler: @Sendable (_ accessToken: String) async throws -> MeResponse
    var listHouseholdsHandler: @Sendable (_ accessToken: String) async throws -> [Household]
    var createHouseholdHandler: @Sendable (_ name: String, _ accessToken: String) async throws -> CreateHouseholdResponse
    var setActiveHouseholdHandler: @Sendable (_ householdID: String, _ accessToken: String) async throws -> ActiveHouseholdResponse
    var deleteAccountHandler: @Sendable (_ accessToken: String) async throws -> Void
    var updateProfileHandler: @Sendable (_ displayName: String, _ profileMediaID: String?, _ accessToken: String) async throws -> MeResponse

    func fetchMe(accessToken: String) async throws -> MeResponse {
        try await fetchMeHandler(accessToken)
    }

    func listHouseholds(accessToken: String) async throws -> [Household] {
        try await listHouseholdsHandler(accessToken)
    }

    func createHousehold(name: String, accessToken: String) async throws -> CreateHouseholdResponse {
        try await createHouseholdHandler(name, accessToken)
    }

    func setActiveHousehold(_ householdID: String, accessToken: String) async throws -> ActiveHouseholdResponse {
        try await setActiveHouseholdHandler(householdID, accessToken)
    }

    func deleteAccount(accessToken: String) async throws {
        try await deleteAccountHandler(accessToken)
    }

    func updateProfile(displayName: String, profileMediaID: String? = nil, accessToken: String) async throws -> MeResponse {
        try await updateProfileHandler(displayName, profileMediaID, accessToken)
    }

    static let live = AccountService(
        fetchMeHandler: { accessToken in
            try await APIClient.live.get("/me", accessToken: accessToken)
        },
        listHouseholdsHandler: { accessToken in
            let response: HouseholdListResponse = try await APIClient.live.get("/households", accessToken: accessToken)
            return response.households
        },
        createHouseholdHandler: { name, accessToken in
            try await APIClient.live.post(
                "/households",
                body: CreateHouseholdRequest(name: name),
                accessToken: accessToken
            )
        },
        setActiveHouseholdHandler: { householdID, accessToken in
            try await APIClient.live.post(
                "/me/active-household",
                body: SetActiveHouseholdRequest(householdId: householdID),
                accessToken: accessToken
            )
        },
        deleteAccountHandler: { accessToken in
            try await APIClient.live.delete("/me/account", accessToken: accessToken)
        },
        updateProfileHandler: { displayName, profileMediaID, accessToken in
            try await APIClient.live.patch(
                "/me",
                body: UpdateProfileRequest(displayName: displayName, profileMediaId: profileMediaID),
                accessToken: accessToken
            )
        }
    )

    static let preview = AccountService(
        fetchMeHandler: { _ in
            MeResponse(
                human: CurrentUser(id: "hum_preview", email: "logan@example.com", displayName: "Logan", profileMediaId: "preview"),
                activeHouseholdId: "hhd_preview"
            )
        },
        listHouseholdsHandler: { _ in
            [Household(id: "hhd_preview", name: "Home", role: "owner", createdAt: nil)]
        },
        createHouseholdHandler: { name, _ in
            CreateHouseholdResponse(
                household: Household(id: "hhd_preview", name: name, role: "owner", createdAt: nil),
                accessToken: "preview-access"
            )
        },
        setActiveHouseholdHandler: { _, _ in
            ActiveHouseholdResponse(accessToken: "preview-access", tokenType: "Bearer")
        },
        deleteAccountHandler: { _ in },
        updateProfileHandler: { displayName, _, _ in
            MeResponse(
                human: CurrentUser(id: "hum_preview", email: "logan@example.com", displayName: displayName, profileMediaId: "preview"),
                activeHouseholdId: nil
            )
        }
    )
}
