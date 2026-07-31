package com.pgmanager.auth;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface UserLoginRepository extends JpaRepository<UserLogin, Long> {

    /**
     * Looks up a login by username, <b>case-insensitively</b>.
     *
     * <p>This is explicit rather than a derived {@code findByUsername} because it has to be.
     * Under MySQL the column collation was {@code utf8mb4_0900_ai_ci}, so {@code =} on any
     * string was already case-insensitive and an owner could sign in with whatever casing they
     * happened to type. PostgreSQL compares strings byte-exactly, so a plain equality lookup
     * would silently start rejecting a correct password typed with the wrong case — a login
     * failure with no error to trace, on the one code path nobody can work around.
     *
     * <p>Tenant ({@code {mobile}@{orgId}}) and manager ({@code {mobile}@m{orgId}}) usernames are
     * generated and contain no letters that vary, so only owner-chosen usernames are actually
     * affected — but that is exactly the set a human types from memory.
     *
     * <p>{@code uk_user_login_username_lower} backs this so it stays an index scan, and it also
     * preserves the old uniqueness semantics: under the previous collation the {@code UNIQUE}
     * constraint already treated "Foo" and "foo" as the same username, and that index keeps
     * them so.
     */
    @Query("SELECT u FROM UserLogin u WHERE LOWER(u.username) = LOWER(:username)")
    Optional<UserLogin> findByUsername(@Param("username") String username);

    /** Case-insensitive for the same reason as {@link #findByUsername}. */
    @Query("SELECT COUNT(u) > 0 FROM UserLogin u WHERE LOWER(u.username) = LOWER(:username)")
    boolean existsByUsername(@Param("username") String username);

    boolean existsByRoleTypeId(String roleTypeId);
}
