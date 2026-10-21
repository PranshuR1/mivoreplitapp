-- Device b37a76e0-6e80-4c90-b702-689613c5d04e is now permanently exempted from
-- device binding client-side (see DeviceBindingService.exemptInstallationIDs /
-- RemoteAuthService.claimDevice in the app). Clear its current row so it starts
-- clean; the client-side exemption stops it from ever being re-claimed.
delete from public.device_bindings
where device_id = 'b37a76e0-6e80-4c90-b702-689613c5d04e';
