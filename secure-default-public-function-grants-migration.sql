-- New public-schema functions must not become callable through PostgREST by default.
-- Existing application RPCs keep their explicit grants; trigger/internal functions remain restricted.
-- Any new public RPC must explicitly GRANT EXECUTE to the intended role(s).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
