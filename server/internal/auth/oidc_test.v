module auth

import x.json2
import time

fn claims_payload(iss string, aud string, exp i64, nbf i64) map[string]json2.Any {
	body := '{"iss":"${iss}","aud":"${aud}","exp":${exp},"nbf":${nbf}}'
	return json2.decode[json2.Any](body) or { panic('bad fixture json') }.as_map()
}

fn test_validate_oidc_claims_accepts_matching_current_token() {
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net',
		expected_audience, now + 3600, now - 60)
	validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') or {
		assert false
	}
}

fn test_validate_oidc_claims_tolerates_issuer_trailing_slash() {
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net/',
		expected_audience, now + 3600, now - 60)
	validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') or {
		assert false
	}
}

fn test_validate_oidc_claims_rejects_wrong_issuer() {
	now := time.now().unix()
	payload := claims_payload('https://attacker.example', expected_audience, now + 3600, now - 60)
	if _ := validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') {
		assert false
	}
}

fn test_validate_oidc_claims_rejects_wrong_audience() {
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net',
		'api://some-other-service', now + 3600, now - 60)
	if _ := validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') {
		assert false
	}
}

fn test_validate_oidc_claims_rejects_expired_token() {
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net',
		expected_audience, now - 3600, now - 7200)
	if _ := validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') {
		assert false
	}
}

fn test_validate_oidc_claims_rejects_not_yet_valid_token() {
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net',
		expected_audience, now + 3600, now + 1800)
	if _ := validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') {
		assert false
	}
}

fn test_validate_oidc_claims_tolerates_small_clock_skew() {
	// Within clock_skew_secs of expiring or becoming valid, must still
	// pass. This is exactly the margin clock_skew_secs is for.
	now := time.now().unix()
	payload := claims_payload('https://authorization.franchise.minecraft-services.net',
		expected_audience, now - 30, now - 60)
	validate_oidc_claims(payload, 'https://authorization.franchise.minecraft-services.net') or {
		assert false
	}
}

fn test_audience_matches_accepts_array_form() {
	body := '{"aud":["${expected_audience}","api://something-else"]}'
	payload := json2.decode[json2.Any](body)!.as_map()
	assert audience_matches(payload)
}

fn test_audience_matches_rejects_missing_audience() {
	payload := json2.decode[json2.Any]('{}')!.as_map()
	assert !audience_matches(payload)
}
