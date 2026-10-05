# SSH key pair. The public key is hardcoded here (per the demo's design). The private half
# never leaves your machine; AWS only ever stores the public key below.
resource "aws_key_pair" "this" {
  key_name   = "${var.app_name}-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC2c6sok8GrDmVHN8rUorRJdv6MHSOTPRxogl5N+3TFxJldRcqqI2ig45w/fTcQsh/nwoEtZXEtZbrBO49ou7XSBCVpUuWRuWeLod6nKvlU9I6SMHe2VKEXpjd02uV+48kbUcxqoqmMqhmVeX5uEnYCKs1DhM+YesD9nkZtQpHqmfOUA4iNhn7QctBfexFVwQkQh6ZarpMn84km+MFd8KmMfqw8J2G2yIR0GErlRGI39G8k0I2BHBmbGSiUbJUXOb2uZeFNfnYlkpnKOBiKwJyV0YFgKtPa1/ghykTR8Q/nSk4XHyuXdEoVK8j8NvLMX39tOh+I7q0eJsfmrABRCET5oRSg4ky22LPQ0TdsD/uB6LddCfGSsRxFVDwL54y1Elijl7/GugYwTY2jOmu3tKCeATjERp0asPsFSRc+sESWzyVsqXvosHqhLWY/rNFTft2b1ejFnfKrQ3MB71mIN16eb9Nu5DPvuS71ILWSB4r5g4ctRLdOgxUEDWmnGqzMr329nIrvBBLkRxgSkBjq+PMFEBAjQa9qOJmp7c04QRNfJFnU0s2l1B/s+ICiZSOAnzyKZfEkOTbV3ymvQdyVJcdCvxR7bL2FqOqxum8Jr6pyNkeYFxB9A0gXovoVNLt/DLXfwuSj0zkohZqYwltOvz53gQVj0EATto4nH3+DjzrrtQ=="

  tags = { Name = "${var.app_name}-key" }
}
