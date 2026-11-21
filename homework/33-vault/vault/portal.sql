CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
GRANT CONNECT ON DATABASE portal TO "{{name}}";
GRANT USAGE ON SCHEMA public TO "{{name}}";
GRANT SELECT, INSERT ON TABLE public.visits TO "{{name}}";
GRANT USAGE ON SEQUENCE public.visits_id_seq TO "{{name}}";
