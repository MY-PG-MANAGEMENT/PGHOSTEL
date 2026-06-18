package com.pgmanager.security;

import com.pgmanager.auth.UserLogin;
import com.pgmanager.auth.UserLoginRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AppUserDetailsService implements UserDetailsService {
    private final UserLoginRepository userLoginRepository;

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        UserLogin user = userLoginRepository.findByUsername(username)
                .orElseThrow(() -> new UsernameNotFoundException("Invalid username"));
        return new AppUserPrincipal(
                user.getUserLoginId(),
                user.getPartyId(),
                user.getOrganizationId(),
                user.getUsername(),
                user.getPasswordHash(),
                user.getRoleTypeId(),
                user.getStatus()
        );
    }
}
