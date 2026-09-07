const objectIdentifierClaim = "http://schemas.microsoft.com/identity/claims/objectidentifier";
const roleClaim = "userRoles";
const groupClaimTypes = new Set(["groups", "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups"]);

function isLocalDevelopment() {
  return process.env.LOCAL_DEVELOPMENT === "true";
}

function localPrincipal() {
  const roles = (process.env.LOCAL_USER_ROLES ?? "authenticated,user,admin")
    .split(",")
    .map((role) => role.trim())
    .filter(Boolean);

  return {
    objectId: process.env.LOCAL_USER_ID ?? "local-developer",
    roles,
    groups: []
  };
}

function claimValues(claims, type) {
  return claims.filter((claim) => claim.typ === type).map((claim) => claim.val);
}

export function getPrincipal(request) {
  const clientPrincipalHeader = request.headers.get("x-ms-client-principal");
  if (!clientPrincipalHeader) {
    return isLocalDevelopment() ? localPrincipal() : null;
  }

  try {
    const principal = JSON.parse(Buffer.from(clientPrincipalHeader, "base64").toString("utf8"));
    const claims = principal.claims ?? [];
    const objectId = claimValues(claims, objectIdentifierClaim)[0] ?? principal.userId;
    const roles = claimValues(claims, roleClaim)[0]?.split(",") ?? principal.userRoles ?? [];
    const groups = claims.filter((claim) => groupClaimTypes.has(claim.typ)).map((claim) => claim.val);

    return objectId ? { objectId, roles, groups } : null;
  } catch {
    return null;
  }
}

export function requirePrincipal(request) {
  const principal = getPrincipal(request);
  if (!principal) {
    throw new Error("Authentication is required.");
  }

  return principal;
}

export function requireAdmin(principal) {
  if (!principal.roles.map((role) => role.toLowerCase()).includes("admin")) {
    throw new Error("Administrator access is required.");
  }
}

export function isSessionOwner(session, principal) {
  return session.ownerId === principal.objectId;
}

export function resolveRoles(principal, adminGroupId, userGroupId) {
  const normalizedGroups = new Set(principal.groups.map((group) => group.toLowerCase()));
  const roles = ["authenticated"];

  if (adminGroupId && normalizedGroups.has(adminGroupId.toLowerCase())) {
    roles.push("admin", "user");
  } else if (userGroupId && normalizedGroups.has(userGroupId.toLowerCase())) {
    roles.push("user");
  }

  return roles;
}
