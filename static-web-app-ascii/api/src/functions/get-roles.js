import { app } from "@azure/functions";
import { getPrincipal, resolveRoles } from "../services/authorization.js";

app.http("GetRoles", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "GetRoles",
  handler: async (request) => {
    const principal = getPrincipal(request);
    if (!principal) {
      return { status: 401, jsonBody: { error: "Authentication is required." } };
    }
    return {
      jsonBody: {
        roles: resolveRoles(principal, process.env.ADMIN_GROUP_ID, process.env.USER_GROUP_ID)
      }
    };
  }
});
