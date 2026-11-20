/// Basic UPI Virtual Payment Address format validation.
/// The PSP/bank remains responsible for confirming that the VPA actually exists.
bool isValidUpiVpa(String value) {
  final vpa = value.trim();
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,255}@[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
      .hasMatch(vpa);
}
